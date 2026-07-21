# eigen_api.api.BotWebhookApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**botAction**](BotWebhookApi.md#botaction) | **POST** /api/bot/action | 


# **botAction**
> botAction(botAction)



### Example
```dart
import 'package:eigen_api/api.dart';
// TODO Configure API key authorization: botHmac
//defaultApiClient.getAuthentication<ApiKeyAuth>('botHmac').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('botHmac').apiKeyPrefix = 'Bearer';

final api = EigenApi().getBotWebhookApi();
final BotAction botAction = ; // BotAction | 

try {
    api.botAction(botAction);
} catch on DioException (e) {
    print('Exception when calling BotWebhookApi->botAction: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **botAction** | [**BotAction**](BotAction.md)|  | 

### Return type

void (empty response body)

### Authorization

[botHmac](../README.md#botHmac)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

