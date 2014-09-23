#!/usr/bin/perl
#
# Author: Amy Finkbiner
# Date: 2014-09-20
#
# Given a target user, this script computes a feature vector and class
# label for every possible pair of the user's friends.  The feature
# vector is based on Facebook profile data, and the class label
# indicates whether an edge exists between the pair (i.e., whether
# they are friends with each other).
#
# In the Kaggle data, the largest number of friends connected to a
# single user is 781, for user 23978.  Therefore, the largest number
# of pairs we will need to consider is 781*780/2 = 304590, which is
# manageable even with my computing constraints.
#
# Key inputs:
#   <target_user>.egonet: This file lists the friendships between the
#     target user's friends.  Assumed to be stored at
#     <data_directory>/egonets/<target_user>.egonet
#   features.txt: This file contains Facebook profile data for all
#     users.  Assumed to be stored at <data_directory>/features.txt
#
# Note: I would normally separate the wrapper functionality (looping
# through the egonet files in the directory) from the computations,
# but I combined them in this case for ease of email delivery.
#
#################
use strict;     #
use warnings;   #
use File::Spec; #
#################

die ("Call: $0 <source_directory> <output_directory>\n")
    unless (scalar (@ARGV) == 2);
my ($source_directory, $output_directory) = @ARGV;

my $profile_file = File::Spec->catfile ($source_directory, "features.txt");

########################################
# Get the names of all the egonet files.
my $egonet_directory = File::Spec->catfile ($source_directory, "egonets");
opendir (DIR, $egonet_directory)
    or die ("Could not open $egonet_directory: $!");
my @files = readdir (DIR);
closedir (DIR);

########################################
# Loop through the egonet files, computing a feature vector file
# for each one.
foreach my $file (sort @files) {
    if ($file =~ /^(\d+)\.egonet$/) {
	my $targetID = $1;
	print STDERR "User $targetID...\n";

	######################################################################
	# Ingest the egonet.  Create a data structure that identifies
	# which of the target user's friends are connected to each
	# other (mutual friends).  Also create a list of all friends'
	# IDs, to streamline later processing.

	my %connected = ();
	my %friends = ();

	my $egonet_file = File::Spec->catfile ($source_directory,
					       "egonets",
					       $file);
	open (IN, "<$egonet_file") or die ("Could not open $egonet_file: $!");
	while (my $line = <IN>) {
	    ########################################
	    # Each line provides information about one of the target user's
	    # friends.  The friend's ID appears first, followed by a colon,
	    # then a space-separated list of all the target user's friends
	    # whom this friends is also friends with.
	    my ($friend, @mutual_friends) = split (' ', $line);
	    $friend =~ s/://;

	    ########################################
	    # Add the friend to the list for later use.
	    $friends{$friend} = 1;

	    ########################################
	    # Add the friend's connections to all the mutual friends.
	    # Because Facebook connections are undirected, we can sort
	    # the IDs numerically and just store the connection
	    # between them once.
	    foreach my $mutual (@mutual_friends) {
		if ($friend < $mutual) {
		    $connected{$friend}{$mutual} = 1;
		} else {
		    $connected{$mutual}{$friend} = 1;
		}
	    }
	}
	close (IN);

	######################################################################
	# Ingest the profile data.  Create a data structure that
	# tracks all observed feature values.  Note that some features
	# appear more than once for a single user, e.g., if they
	# provide the names of both their high school and their
	# university, so we must track all of them.  Also create a
	# list of all the observed features, to streamline later
	# processing.

	my %profile = ();
	my %features = ();

	open (IN, "<$profile_file") or die ("Could not open $profile_file: $!");
	while (my $line = <IN>) {
	    my ($userID, @features) = split (' ', $line);

	    ########################################
	    # We only need to pay attention to people in the current egonet.
	    # We don't need the target user, just their friends.
	    next unless ($friends{$userID});

	    foreach my $feature (@features) {
		########################################
		# This regular expression divides the string into two parts
		# based on the final semicolon, e.g.,
		# * "birthday;123" -> "birthday" and "123"
		# * "education;school;id;456" -> "education;school;id" and "456"
		$feature =~ /^(.+);([^;]+)$/;
		my $feature_name = $1;
		my $feature_value = $2;

		next if ($feature_name eq 'id');
		next if ($feature_name =~ /;name$/);

		########################################
		# Add the feature to the list for later use.
		$features{$feature_name} = 1;

		########################################
		# The following structure records all the observed values of
		# $feature_name for the $userID.  Storing $feature_value as
		# hash keys instead of an array will make comparisons between
		# users easier later on.
		$profile{$userID}{$feature_name}{$feature_value} = 1;
	    }
	}
	close (IN);

	######################################################################
	# Loop through all pairs, creating the class label and feature
	# vector.

	my $output_file = File::Spec->catfile ($output_directory,
					       "$targetID.csv");
	open (OUT, ">$output_file") or die ("Could not open $output_file: $!");

	my @friends = sort {$a <=> $b} keys %friends; # numeric sort
	my @features = sort keys %features; # string sort

	printf OUT ("pair,edge,common_friends,%s\n",
		       join (',', @features));

	for (my $i=0; $i<scalar(@friends); $i++) {
	    for (my $j=$i+1; $j<scalar(@friends); $j++) {

		########################################
		# The class label is simply whether the i^th and j^th friends
		# are friends with each other (connected by an edge).
		my $edge = $connected{$friends[$i]}{$friends[$j]} ?
		    'TRUE' : 'FALSE';

		########################################
		# The feature vector simply counts the number of values the
		# two users have in common, for each available feature.
		my @feature_vector = ();
		foreach my $feature (@features) {
		    push (@feature_vector,
			  count_common_feature_values ($feature,
						       $friends[$i],
						       $friends[$j],
						       \%profile));
		}

		########################################
		# Export the results.
		printf OUT ("%s;%s,%s,%s,%s\n",
			    $friends[$i],
			    $friends[$j],
			    $edge,
			    count_common_friends ($friends[$i],
						  $friends[$j],
						  \@friends,
						  \%connected),
			    join (',', @feature_vector));
	    }
	}

	close (OUT);

    }
}

######################################################################
##### SUBROUTINES ####################################################
######################################################################

sub is_connected {
    my ($user1, $user2, $edges) = @_;

    if ($user1 < $user2) {
	return ($edges->{$user1}{$user2});
    } else {
	return ($edges->{$user2}{$user1});
    }
}

sub count_common_friends {
    my ($user1, $user2, $friends, $edges) = @_;
    my $matched = 0;

    foreach my $id (@$friends) {
	$matched++ if (is_connected ($user1, $id, $edges) &&
		       is_connected ($user2, $id, $edges));
    }

    return ($matched);
}

sub count_common_feature_values {
    my ($feature, $user1, $user2, $profile) = @_;
    my $matched = 0;

    foreach my $value (keys %{$profile->{$user1}{$feature}}) {
	$matched++ if ($profile->{$user2}{$feature}{$value});
    }

    return ($matched);
}
