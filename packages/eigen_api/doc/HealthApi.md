# eigen_api.api.HealthApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getHealth**](HealthApi.md#gethealth) | **GET** /health | Liveness probe


# **getHealth**
> Health getHealth()

Liveness probe

Public, unauthenticated liveness check. Performs no I/O and reads no configuration, so a 200 means only that the worker is deployed and routable — it does **not** imply that D1, the game Durable Objects, or auth are correctly configured. Served `no-store`. Safe to call without a token; a bad token is ignored rather than rejected.

### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getHealthApi();

try {
    final response = api.getHealth();
    print(response);
} catch on DioException (e) {
    print('Exception when calling HealthApi->getHealth: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**Health**](Health.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

