#' A result metric (RM) that calculates confusion matrices
#'
#' This result metric calculate a confusion matrices from all points in time.
#' 
#' @details
#' Like all result metrics, this result metric has functions to aggregregate
#' results after completing each set of cross-validation classifications, and
#' also after completing all the resample runs. The results should then be
#' available in the DECODING_RESULTS object returned by the cross-validator.
#'
#' @param save_only_same_train_test_time A boolean specifying whether one wants
#'  to create the confusion matrices when training at one point in time and
#'  testing a different point in time. This usually is not necessary and takes 
#'  up more memeory.
#' 
#' @param create_decision_vals_confusion_matrix A boolean specifying whether one wants
#'  to create the create a confusion matrix of the decision values. In this confusion
#'  matrix, each row corresponds to the correct class (like a regular confusion matrix)
#'  and each column corresponds to the mean decision value of the predictions for 
#'  each class. 
#' 
#' @examples
#' # If you only want to use the rm_confusion_matrix(), then you can put it in a
#' # list by itself and pass it to the cross-validator.
#' the_rms <- list(rm_confusion_matrix())
#' 
#' @family result_metrics







# the constructor 
#' @export
rm_confusion_matrix <- function(save_only_same_train_test_time = TRUE, 
                                create_decision_vals_confusion_matrix = TRUE) {
  
  options <- list(save_only_same_train_test_time = save_only_same_train_test_time,
                  create_decision_vals_confusion_matrix = create_decision_vals_confusion_matrix)
  
  new_rm_confusion_matrix(data.frame(), 'initial', options)

}





# the internal constructor
new_rm_confusion_matrix <- function(the_data = data.frame(), 
                                    the_state = NULL,
                                    options = NULL) {
  
  rm_obj <- the_data
  attr(rm_obj, "state") <- the_state
  attr(rm_obj, "options") <- options
  attr(rm_obj, "class") <- c("rm_confusion_matrix", 'data.frame')
  
  rm_obj
  
}





# The aggregate_CV_split_results method needed to fulfill the results metric interface
#' @export
aggregate_CV_split_results.rm_confusion_matrix = function(rm_obj, prediction_results) {
  

  # include a warning if the state is not intial
  if (attr(rm_obj, "state") != "initial") {    
    warning(paste0("The method aggregate_CV_split_results() should only be called on",
                   "normalized_rank_and_decision_values_RM that are in the intial state.",
                   "Any data that was already stored in this object will be overwritten"))
  }
  
  
  # If specied in the constructur, save the confusion matrix only for training and testing 
  # the same times. This will save memory, and the off diagonal element confusion matrices 
  # can't generally of too much interest (however they could be of interest when 
  # converting the confusion matrix to mutual information). 
  
  options <- attr(rm_obj, 'options')
  
  if (options$save_only_same_train_test_time) {
    prediction_results <- prediction_results %>% 
      dplyr::filter(.data$train_time == .data$test_time)  
  }
  
  
  # create the confusion matrix
  confusion_matrix <- prediction_results %>%
    dplyr::group_by(.data$train_time, .data$test_time, .data$actual_labels, .data$predicted_labels) %>%
    summarize(n = n())
  
  
  if (options$create_decision_vals_confusion_matrix) {
    
    # create the decision value confusion matrix
    confusion_matrix_decision_vals <- prediction_results %>%
      select(-.data$predicted_labels, -.data$CV) %>%
      dplyr::group_by(.data$train_time, .data$test_time, .data$actual_labels) %>%
      summarize_all(mean) %>%
      tidyr::pivot_longer(starts_with("decision_vals"), names_to = "predicted_labels", 
                        values_to = "mean_decision_vals") %>%
      mutate(predicted_labels = gsub("decision_vals.", "", .data$predicted_labels))
  
    confusion_matrix <- left_join(confusion_matrix_decision_vals, confusion_matrix, 
                                   by = c("train_time", "test_time", "actual_labels", "predicted_labels")) 
    
    confusion_matrix$n[is.na(confusion_matrix$n)] = 0
    
  }
  
  
  # # Adding this instead to the final aggregation step to save a little memory.
  # # However, doing it here has only a small advantage of making the confusion matrices 
  # # from all runs are the same size (but saving memory seems more important).
  # 
  # # add on 0's for all entries in the confusion matrix that are missing
  # empty_cm <-  expand.grid(resample_run = "0",
  #                          train_time = unique(confusion_matrix$train_time),
  #                          test_time = unique(confusion_matrix$test_time),
  #                          actual_labels = unique(confusion_matrix$actual_labels),
  #                          predicted_labels= unique(confusion_matrix$predicted_labels),
  #                          n = 0L, stringsAsFactors = FALSE)
  # 
  # confusion_matrix <- dplyr::bind_rows(confusion_matrix, empty_cm)
  # 
  # # add in the zero results...
  # confusion_matrix <-  confusion_matrix %>% 
  #   dplyr::group_by(train_time,  test_time, actual_labels,  predicted_labels) %>%
  #   summarize(n = sum(n))
  
  
  new_rm_confusion_matrix(confusion_matrix, 
                          'results combined over one cross-validation split', 
                          attr(rm_obj, 'options'))
  
}







# The aggregate_resample_run_results method needed to fulfill the results metric interface
#' @export
aggregate_resample_run_results.rm_confusion_matrix = function(resample_run_results) {


  confusion_matrix <- resample_run_results 

  # add on 0's for all entries in the confusion matrix that are missing  -----------------------------------------

  # check if only specified that one should only save the results at the same training and test time
  #  or if the results only were recorded for the same train and test times (since this was specied in the CV obj)
  options <- attr(resample_run_results, 'options')
  only_has_same_train_test_time_results <- 
    (sum(resample_run_results$train_time == resample_run_results$test_time) == dim(resample_run_results)[1])
  
  if (options$save_only_same_train_test_time || only_has_same_train_test_time_results) {

    # create smaller matrix of 0's if only saving results of training and testing at the same time
    cm_label_matrix <- expand.grid(actual_labels = unique(confusion_matrix$actual_labels),
                             predicted_labels = unique(confusion_matrix$predicted_labels))
    
    time_matrix <- data.frame(train_time = unique(confusion_matrix$train_time),
                              test_time = unique(confusion_matrix$test_time))
    
    empty_cm  <- data.frame(resample_run = "0",
                             time_matrix[rep(1:dim(time_matrix)[1], dim(cm_label_matrix)[1]), ],
                             cm_label_matrix[rep(1:dim(cm_label_matrix)[1], each = dim(time_matrix)[1]), ],
                             n = 0L)
    
    # could just filter the results below using train_time == test_time but this would require a lot more memory
    
  } else {
    
    empty_cm <-  expand.grid(resample_run = "0",
                             train_time = unique(confusion_matrix$train_time),
                             test_time = unique(confusion_matrix$test_time),
                             actual_labels = unique(confusion_matrix$actual_labels),
                             predicted_labels= unique(confusion_matrix$predicted_labels),
                             n = 0L, stringsAsFactors = FALSE)
  }

  
  
  confusion_matrix <- dplyr::bind_rows(confusion_matrix, empty_cm)

  
  # calculate the final confusion matrix
  confusion_matrix <-  confusion_matrix %>%
    dplyr::group_by(.data$train_time,  .data$test_time, .data$actual_labels,  .data$predicted_labels) %>%
    summarize(n = sum(n)) %>%
    dplyr::group_by(.data$train_time,  .data$test_time, .data$actual_labels) %>%
    mutate(conditional_pred_freq = n / sum(n))    # Pr(predicted = y | actual = k)
  
  #dplyr::group_by(train_time,  test_time) %>%
  #mutate(predicted_frequency = n / sum(n))   # Pr(predicted = y, actual = k)
  
  
  if (options$create_decision_vals_confusion_matrix) {
    
    confusion_matrix_decision_vals <- resample_run_results %>%
      dplyr::group_by(.data$train_time,  .data$test_time, .data$actual_labels,  .data$predicted_labels) %>%
      summarize(mean_decision_vals = mean(.data$mean_decision_vals))
    
    if (dim(confusion_matrix_decision_vals)[1] != dim(confusion_matrix)[1]){
      warning(paste('Something has gone wrong where the confusion_matrix_decision_vals and",
                    "confusion_matrix do not have the same number of rows'))
    }
    
    confusion_matrix <- confusion_matrix %>%
      left_join(confusion_matrix_decision_vals, 
                by = c("train_time", "test_time", "actual_labels", "predicted_labels"))
    
  }
  
  
  new_rm_confusion_matrix(confusion_matrix, 
                          'final results', 
                          attr(resample_run_results, 'options'))
  
}





#' plot the confusion matrix results
#'
#' This function plots confusion matrices after the decoding analysis has been
#' run (and all results have been aggregated)
#' 
#' @param x A rm_confusion_matrix object that has aggregated
#'   runs from a decoding analysis, e.g., if DECODING_RESULTS are the out from
#'   the run_decoding(cv) then this argument should be
#'   DECODING_RESULTS$rm_confusion_matrix.
#' 
#' @param ... This is needed to conform to the plot generic interface
#' 
#' @param plot_only_same_train_test_time A boolean indicating whether
#'   the confusion matrices should only be plotted at the same training 
#'   and test times.
#'   
#' @param plot_decision_vals_confusion_matrix A boolean that if set to 
#'  TRUE will cause the decision value confusion matrix to be plotted
#'  instead of the zero-one loss (i.e., normal) confusion matrix to be
#'  plotted. 
#' 
#' @family result_metrics


#' @export
plot.rm_confusion_matrix = function(x, ..., plot_only_same_train_test_time = FALSE,
                                    plot_decision_vals_confusion_matrix = FALSE) {

  
  confusion_matrix_obj <- x
  
  
  # should perhaps give an option to choose a different color scale, and maybe other options? 
  
  # checking if only have the results for training and testing at the same time
  # could look at the 'options' attribute for this, but that won't help if the filtering happened at the
  # level of the cross-validator
  only_has_same_train_test_time_results <- 
    (sum(confusion_matrix_obj$train_time == confusion_matrix_obj$test_time) == dim(confusion_matrix_obj)[1])

  confusion_matrix_obj$train_time <- round(get_center_bin_time(confusion_matrix_obj$train_time))
  confusion_matrix_obj$test_time <- round(get_center_bin_time(confusion_matrix_obj$test_time))

  #confusion_matrix_obj$train_time <- get_time_range_strings(confusion_matrix_obj$train_time)
  #confusion_matrix_obj$test_time <- get_time_range_strings(confusion_matrix_obj$test_time)
  
  
  # if only want the results plotted for the same training and test times
  if (!only_has_same_train_test_time_results && plot_only_same_train_test_time) {
    confusion_matrix_obj <- confusion_matrix_obj %>%
      filter(.data$train_time == .data$test_time)
  }
  

  if (FALSE) {  #(only_has_same_train_test_time_results) {
    
    # Add the word 'Time' to the title since there is enough space to plot it 
    # when only training and testing at the same time
    
    train_time_order <- paste('Time', unique(sort(confusion_matrix_obj$train_time)))
    confusion_matrix_obj$train_time <- ordered(
      paste('Time', confusion_matrix_obj$train_time),
      levels = train_time_order 
    )
    
    test_time_order <- paste('Time', unique(sort(confusion_matrix_obj$test_time)))
    confusion_matrix_obj$test_time <- ordered(
      paste('Time', confusion_matrix_obj$test_time),
      levels = test_time_order 
    )
    
  }
  
  
  if (plot_decision_vals_confusion_matrix){
    
    g <- confusion_matrix_obj %>%
      ggplot(aes(.data$predicted_labels, forcats::fct_rev(.data$actual_labels), fill = .data$mean_decision_vals)) +
      geom_tile() + 
      theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
      ylab('True class') + 
      xlab('Predicted class') +    # or should I transpose this (people do it differently...)
      scale_fill_continuous(type = "viridis", name = "Mean\n decision\n value") #+ 
    
    
  } else {
    
    g <- confusion_matrix_obj %>%
      ggplot(aes(.data$predicted_labels, forcats::fct_rev(.data$actual_labels), fill = .data$conditional_pred_freq * 100)) +
      geom_tile() + 
      theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
      ylab('True class') + 
      xlab('Predicted class') +    # or should I transpose this (people do it differently...)
      scale_fill_continuous(type = "viridis", name = "Prediction\n frequency") #+ 
  }


  
  if (sum(confusion_matrix_obj$train_time == confusion_matrix_obj$test_time) == dim(confusion_matrix_obj)[1]){
    g + facet_wrap(~.data$train_time)
  } else {    
    g + facet_grid(.data$train_time ~ .data$test_time)
  } 
  
  
  
}







#' plot the mutual information computed from a confusion matrix
#'
#' This function can plot line results or temporal cross-decoding results for
#' the the zero-one loss, normalized rank and/or decision values after the
#' decoding analysis has been run (and all results have been aggregated)
#' 
#' @param rm_obj A rm_confusion_matrix object that has aggregated
#'   runs from a decoding analysis, e.g., if DECODING_RESULTS are the out from
#'   the run_decoding(cv) then this argument should be
#'   DECODING_RESULTS$rm_confusion_matrix.
#' 
#' @param plot_type A string specifying the type of results to plot. Options are
#'   'TCD' to plot a temporal cross decoding matrix or 'line' to create a line
#'   plot of the decoding results as a function of time
#' 
#' @family result_metrics
#' 
#' @export
plot_MI.rm_confusion_matrix = function(rm_obj, plot_type = 'TCD') {
  
  
  if (!(plot_type == 'TCD' || plot_type == 'line'))
    warning("plot_type must be set to 'TCD' or 'line'. Using the default value of 'TCD'")
  
  
  # calculate the mutual information ------------------------------------------
  
  MI_obj <-  rm_obj %>%
    group_by(.data$train_time,  .data$test_time) %>%
    mutate(joint_probability = n/sum(n))   %>%
    group_by(.data$train_time,  .data$test_time, .data$actual_labels) %>%
    mutate(log_marginal_actual = log2(sum(.data$joint_probability))) %>%
    group_by(.data$train_time,  .data$test_time, .data$predicted_labels) %>%
    mutate(log_marginal_predicted = log2(sum(.data$joint_probability))) %>%
    ungroup() %>%
    mutate(log_joint_probability = log2(.data$joint_probability))   %>%
    mutate(log_joint_probability = replace(.data$log_joint_probability, .data$log_joint_probability == -Inf, 0)) %>%
    mutate(MI_piece = .data$joint_probability * (.data$log_joint_probability - .data$log_marginal_actual - .data$log_marginal_predicted)) %>%
    group_by(.data$train_time, .data$test_time) %>%
    summarize(MI = sum(.data$MI_piece))

  
  # plot the mutual information  ----------------------------------------------
  
  MI_obj$train_time <- round(get_center_bin_time(MI_obj$train_time))
  MI_obj$test_time <- round(get_center_bin_time(MI_obj$test_time))
  
  
  if ((sum(MI_obj$train_time == MI_obj$test_time) == dim(MI_obj)[1]) || plot_type == 'line') {
    
    # if only trained and tested at the same time, create line plot
    MI_obj %>%
      dplyr::filter(.data$train_time == .data$test_time) %>%
      ggplot(aes(.data$test_time, .data$MI)) +
      geom_line() +
      xlab('Time') + 
      ylab('Mutual information (bits)') # + 
      # geom_hline(yintercept = 0, color = "red")  # how much MI there should be if there is no bias
    
  } else {
    
    MI_obj %>%
      ggplot(aes(.data$test_time, .data$train_time, fill = .data$MI)) + 
      geom_tile() + 
      ylab('Test time') + 
      xlab('Train time') +    
      scale_fill_continuous(type = "viridis", name = "Bits") + 
      ggtitle("Mutual information") + 
      theme(plot.title = element_text(hjust = 0.5)) 
  }
  
}



#' @export
get_parameters.rm_confusion_matrix = function(ndtr_obj){

  # there is only one parameter option that can be set here so return it  
  data.frame(rm_confusion_matrix.save_only_same_train_test_time = 
               attributes(ndtr_obj)$options$save_only_same_train_test_time,
             rm_confusion_matrix.create_decision_vals_confusion_matrix = 
               attributes(ndtr_obj)$options$create_decision_vals_confusion_matrix)
}




