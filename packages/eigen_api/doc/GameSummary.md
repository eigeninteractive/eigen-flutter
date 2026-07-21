# eigen_api.model.GameSummary

## Load the model package
```dart
import 'package:eigen_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | 
**createdBy** | **String** |  | 
**status** | [**GameStatus**](GameStatus.md) |  | 
**access** | [**GameAccess**](GameAccess.md) |  | 
**schemaVersion** | **int** |  | 
**config** | **Object** |  | 
**turnSeconds** | **int** |  | 
**budgetSeconds** | **int** |  | 
**incrementSeconds** | **int** |  | 
**rated** | **bool** |  | 
**ratingPool** | **String** |  | 
**minPlayers** | **int** |  | 
**maxPlayers** | **int** |  | 
**shortCode** | **String** |  | 
**pendingPlayers** | **List&lt;int&gt;** |  | 
**turnDeadline** | **int** |  | 
**outcomes** | [**List&lt;Outcome&gt;**](Outcome.md) |  | 
**ratings** | [**List&lt;RatingDelta&gt;**](RatingDelta.md) |  | [optional] 
**finishedAt** | **int** |  | 
**createdAt** | **int** |  | 
**updatedAt** | **int** |  | 
**participants** | [**List&lt;Seat&gt;**](Seat.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


