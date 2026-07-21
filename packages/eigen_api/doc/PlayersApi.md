# eigen_api.api.PlayersApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getPlayers**](PlayersApi.md#getplayers) | **GET** /api/engine/players | 


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

