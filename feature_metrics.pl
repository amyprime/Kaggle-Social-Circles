#!/usr/bin/perl
#
# Author: Amy Finkbiner
# Date: 2014-09-20
#
# For each feature in the profile data file, this script computes the
# number of times it occurs, the number of distinct values it takes
# on, the number of unique users it occurs for, and its estimated
# entropy.
#
# Note that some features appear more than once for a single user,
# e.g., if they provide the names of both their high school and their
# university.
#
###############
use strict;   #
use warnings; #
###############

die ("Call: $0 <features.txt>\n")
    unless (scalar (@ARGV) == 1);
my ($profile_file) = @ARGV;

######################################################################
# Ingest the profile data.  Create a data structure that tracks the
# necessary counts.  Also track the total number of unique users for
# later processing.

my %count = ();
my $total_users = 0;

open (IN, "<$profile_file") or die ("Could not open $profile_file: $!");
while (my $line = <IN>) {
    my ($user, @features) = split (' ', $line);

    ########################################
    # Count the total number of distinct users for later use.
    $total_users++;

    foreach my $feature (@features) {
	########################################
	# This regular expression divides the string into two parts
	# based on the final semicolon, e.g.,
	# * "birthday;123" -> "birthday" and "123"
	# * "education;school;id;456" -> "education;school;id" and "456"
	$feature =~ /^(.+);([^;]+)$/;
	my $feature_name = $1;
	my $feature_value = $2;

	########################################
        # The following strucutre records all the necessary counts.
	# * {total} is used for counting total occurrences.
	# * {values} is used for counting distinct values.
	# * {users} is used for both counting distinct users
	#   and computing estimated entropy.
	$count{$feature_name}{total}++;
	$count{$feature_name}{values}{$feature_value} = 1;
	$count{$feature_name}{users}{$user}{$feature_value} = 1;
    }
}
close (IN);

######################################################################
# For each feature, compute and print the desired metrics.

printf STDOUT ("feature,occurrences,unique_users,unique_values,entropy\n");

foreach my $feature_name (sort keys %count) {
    my $unique_users = scalar (keys %{$count{$feature_name}{users}});

    ########################################
    # Compute the estimated entropy.  Start by computing the frequency
    # of each feature value.  For features that occur more than once
    # for a single user, define the value for that user to be the
    # concatenation of all the values.
    my %frequency = ();
    if ($unique_users < $total_users) {
	$frequency{NULL} = $total_users - $unique_users;
    }
    foreach my $user (keys %{$count{$feature_name}{users}}) {
	my $value = join (',', sort keys %{$count{$feature_name}{users}{$user}});
	$frequency{$value}++;
    }

    ########################################
    # Now we can estimate the entropy from the frequency counts.
    my $entropy = 0;
    foreach my $value (keys %frequency) {
	my $probability = $frequency{$value} / $total_users;
	$entropy -= $probability * log($probability) / log(2);
    }

    ########################################
    # Print the metrics for this feature.
    printf STDOUT ("%s,%s,%s,%s,%s\n",
		   $feature_name,
		   $count{$feature_name}{total},
		   scalar (keys %{$count{$feature_name}{values}}),
		   $unique_users,
		   $entropy);
}
