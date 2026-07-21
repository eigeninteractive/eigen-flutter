# eigen_api.api.SocialApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**acceptFriendRequest**](SocialApi.md#acceptfriendrequest) | **POST** /api/engine/friends/requests/{userId}/accept | 
[**blockUser**](SocialApi.md#blockuser) | **POST** /api/engine/friends/{userId}/block | 
[**getFriendsGames**](SocialApi.md#getfriendsgames) | **GET** /api/engine/friends/games | 
[**listFriendRequests**](SocialApi.md#listfriendrequests) | **GET** /api/engine/friends/requests | 
[**listFriends**](SocialApi.md#listfriends) | **GET** /api/engine/friends | 
[**removeFriend**](SocialApi.md#removefriend) | **DELETE** /api/engine/friends/{userId} | 
[**searchUsers**](SocialApi.md#searchusers) | **GET** /api/engine/users/search | 
[**sendFriendRequest**](SocialApi.md#sendfriendrequest) | **POST** /api/engine/friends/requests | 
[**unblockUser**](SocialApi.md#unblockuser) | **DELETE** /api/engine/friends/{userId}/block | 


# **acceptFriendRequest**
> acceptFriendRequest(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final String userId = userId_example; // String | 

try {
    api.acceptFriendRequest(userId);
} catch on DioException (e) {
    print('Exception when calling SocialApi->acceptFriendRequest: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **blockUser**
> blockUser(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final String userId = userId_example; // String | 

try {
    api.blockUser(userId);
} catch on DioException (e) {
    print('Exception when calling SocialApi->blockUser: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getFriendsGames**
> FriendsGames getFriendsGames(limit, cursor)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final int limit = 56; // int | 
final int cursor = 56; // int | 

try {
    final response = api.getFriendsGames(limit, cursor);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SocialApi->getFriendsGames: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **int**|  | [optional] [default to 20]
 **cursor** | **int**|  | [optional] 

### Return type

[**FriendsGames**](FriendsGames.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listFriendRequests**
> FriendRequests listFriendRequests()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();

try {
    final response = api.listFriendRequests();
    print(response);
} catch on DioException (e) {
    print('Exception when calling SocialApi->listFriendRequests: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**FriendRequests**](FriendRequests.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listFriends**
> Friends listFriends()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();

try {
    final response = api.listFriends();
    print(response);
} catch on DioException (e) {
    print('Exception when calling SocialApi->listFriends: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**Friends**](Friends.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeFriend**
> removeFriend(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final String userId = userId_example; // String | 

try {
    api.removeFriend(userId);
} catch on DioException (e) {
    print('Exception when calling SocialApi->removeFriend: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **searchUsers**
> UserSearch searchUsers(q, limit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final String q = q_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.searchUsers(q, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SocialApi->searchUsers: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **q** | **String**|  | 
 **limit** | **int**|  | [optional] [default to 20]

### Return type

[**UserSearch**](UserSearch.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **sendFriendRequest**
> FriendRequestResult sendFriendRequest(friendTarget)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final FriendTarget friendTarget = ; // FriendTarget | 

try {
    final response = api.sendFriendRequest(friendTarget);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SocialApi->sendFriendRequest: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **friendTarget** | [**FriendTarget**](FriendTarget.md)|  | 

### Return type

[**FriendRequestResult**](FriendRequestResult.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unblockUser**
> unblockUser(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getSocialApi();
final String userId = userId_example; // String | 

try {
    api.unblockUser(userId);
} catch on DioException (e) {
    print('Exception when calling SocialApi->unblockUser: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

