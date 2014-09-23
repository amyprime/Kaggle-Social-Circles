# Author: Amy Finkbiner
# Date: 2014-09-20
#
# This script fits a simple linear logistic regression model,
# generating the predicted probability of an edge (friendship) between
# each pair of users.  These probabilities are exported to a CSV file.
#
# Note: I would normally separate the wrapper functionality (looping
# through the egonet files in the directory) from the computations,
# but I combined them in this case for ease of email delivery.
#
predict.edges <- function (input.directory, output.directory) {
  if (!file.exists(input.directory)) stop ("input.directory does not exist")
  if (!file.exists(output.directory)) stop ("output.directory does not exist")
  
  file.names <- list.files (input.directory)

  # This seems like a case where a for loop is actually appropriate in R
  for (file in file.names) {
    print (file)

    input.file <- paste (input.directory, file, sep="/")
    output.file <- paste (output.directory, file, sep="/")
    
    ########################################
    # Import the data file, and do some cleanup
    egonet.pair.data <- read.csv (input.file)
    # The pair IDs get imported as data; change them to row names
    row.names(egonet.pair.data) <- egonet.pair.data$pair
    egonet.pair.data$pair <- NULL
    # Delete the "name" feature; redundant with
    # first_name, middle_name, last_name
    egonet.pair.data$name <- NULL
    # Remove features that only take on a single value
    egonet.pair.data <- egonet.pair.data[apply(egonet.pair.data, 2, sd)>0]

    ########################################
    # Create a version of the data with all features scaled
    # to mean=0, standard deviation=1, except the "edge"
    # feature (class label TRUE/FALSE)
    egonet.pair.data.scaled <- data.frame(scale(egonet.pair.data[,-1]))
    # Add the "edge" label back in
    egonet.pair.data.scaled$edge <- egonet.pair.data$edge

    ########################################
    # Run linear logistic regression for three different models
    # * profile = only use Facebook profile data (features file)
    # * graph = only use friendship graph data (egonet file)
    # * both = use both sources of data
    glm.profile <- glm (edge ~ . - common_friends,
                        family=binomial, egonet.pair.data.scaled)
    glm.graph <- glm (edge ~ common_friends,
                      family=binomial, egonet.pair.data.scaled)
    glm.both <- glm (edge ~ .,
                     family=binomial, egonet.pair.data.scaled)
    
    ########################################
    # Translate each model's predictions into probabilities
    # by applying the logistic function 1/(1+e^-x)
    prediction.profile <- 1 / (1 + exp(-predict(glm.profile)))
    prediction.graph <- 1 / (1 + exp(-predict(glm.graph)))
    prediction.both <- 1 / (1 + exp(-predict(glm.both)))

    ########################################
    # Export truth and predictions to a new CSV file
    output.data <- data.frame (egonet.pair.data.scaled$edge,
                               prediction.profile,
                               prediction.graph,
                               prediction.both)
    names(output.data) <- c("truth", "profile", "graph", "both")
    write.csv (output.data, file = output.file, quote=FALSE)
  }
}

# These are some commands you can use for exploring the data.
# coeffs.profile <- data.frame(glm.profile$coefficients)
# coeffs.profile[order(coeffs.profile,decreasing=TRUE),,drop=FALSE]
# plot (prediction.profile,
#       pairs$edge + runif(length(pairs$edge))/2,
#       xlab="Prediction", ylab="Truth", xlim=c(0,1))
