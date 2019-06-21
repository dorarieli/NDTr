

load("example_ZD_train_and_test_set.Rda")
rm(train_set, test_set, count_train_set, count_test_set)



test_that("classification results seem reasonable", {
  
  cl <- max_correlation_CL()
  
  prediction_results <- get_predictions(cl, normalized_train_set, normalized_test_set)
  
  accuracies <- prediction_results %>%
    dplyr::group_by(time) %>%
    dplyr::summarize(mean_accuracy = mean(actual_labels == predicted_labels))

  
  expect_gt(filter(accuracies, time == "stimulus")$mean_accuracy, .6)
  expect_lt(filter(accuracies, time == "baseline")$mean_accuracy, .3)
  

})


