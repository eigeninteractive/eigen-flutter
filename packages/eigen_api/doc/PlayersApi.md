# eigen_api.api.PlayersApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getPlayerRatings**](PlayersApi.md#getplayerratings) | **GET** /api/engine/players/{playerId}/ratings | 
[**getPlayers**](PlayersApi.md#getplayers) | **GET** /api/engine/players | 


# **getPlayerRatings**
> Ratings getPlayerRatings(playerId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getPlayersApi();
final String playerId = playerId_example; // String | 

try {
    final response = api.getPlayerRatings(playerId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PlayersApi->getPlayerRatings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **playerId** | **String**|  | 

### Return type

[**Ratings**](Ratings.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getPlayers**
> Players getPlayers(ids)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getPlayersApi();
final String ids = ids_example; // String | 

try {
    final response = api.getPlayers(ids);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PlayersApi->getPlayers: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **ids** | **String**|  | 

### Return type

[**Players**](Players.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

