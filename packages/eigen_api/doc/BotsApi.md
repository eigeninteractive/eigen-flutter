# eigen_api.api.BotsApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getBots**](BotsApi.md#getbots) | **GET** /api/engine/bots | 


# **getBots**
> Bots getBots()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getBotsApi();

try {
    final response = api.getBots();
    print(response);
} catch on DioException (e) {
    print('Exception when calling BotsApi->getBots: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**Bots**](Bots.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

