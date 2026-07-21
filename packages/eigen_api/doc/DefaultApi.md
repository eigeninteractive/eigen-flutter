# eigen_api.api.DefaultApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**acceptFriendRequest**](DefaultApi.md#acceptfriendrequest) | **POST** /api/engine/friends/requests/{userId}/accept | 
[**addBot**](DefaultApi.md#addbot) | **POST** /api/engine/games/{gameId}/add-bot | 
[**blockUser**](DefaultApi.md#blockuser) | **POST** /api/engine/friends/{userId}/block | 
[**botAction**](DefaultApi.md#botaction) | **POST** /api/bot/action | 
[**cancelGame**](DefaultApi.md#cancelgame) | **POST** /api/engine/games/{gameId}/cancel | 
[**createGame**](DefaultApi.md#creategame) | **POST** /api/engine/games | 
[**createSoloGame**](DefaultApi.md#createsologame) | **POST** /api/engine/games/solo | 
[**deleteAccount**](DefaultApi.md#deleteaccount) | **DELETE** /api/engine/me | 
[**forfeitGame**](DefaultApi.md#forfeitgame) | **POST** /api/engine/games/{gameId}/forfeit | 
[**getBots**](DefaultApi.md#getbots) | **GET** /api/engine/bots | 
[**getFrames**](DefaultApi.md#getframes) | **GET** /api/engine/games/{gameId}/frames | 
[**getFriendsGames**](DefaultApi.md#getfriendsgames) | **GET** /api/engine/friends/games | 
[**getGame**](DefaultApi.md#getgame) | **GET** /api/engine/games/{gameId} | 
[**getLobby**](DefaultApi.md#getlobby) | **GET** /api/engine/lobby | 
[**getMyGames**](DefaultApi.md#getmygames) | **GET** /api/engine/games/mine | 
[**getMyRatingHistory**](DefaultApi.md#getmyratinghistory) | **GET** /api/engine/me/rating-history | 
[**getMyRatings**](DefaultApi.md#getmyratings) | **GET** /api/engine/me/ratings | 
[**getPlayers**](DefaultApi.md#getplayers) | **GET** /api/engine/players | 
[**getProfile**](DefaultApi.md#getprofile) | **GET** /api/engine/me | 
[**joinGame**](DefaultApi.md#joingame) | **POST** /api/engine/games/{gameId}/join | 
[**joinGameByCode**](DefaultApi.md#joingamebycode) | **POST** /api/engine/games/join-by-code | 
[**leaveGame**](DefaultApi.md#leavegame) | **POST** /api/engine/games/{gameId}/leave | 
[**listFriendRequests**](DefaultApi.md#listfriendrequests) | **GET** /api/engine/friends/requests | 
[**listFriends**](DefaultApi.md#listfriends) | **GET** /api/engine/friends | 
[**registerDevice**](DefaultApi.md#registerdevice) | **PUT** /api/engine/me/devices | 
[**removeFriend**](DefaultApi.md#removefriend) | **DELETE** /api/engine/friends/{userId} | 
[**searchUsers**](DefaultApi.md#searchusers) | **GET** /api/engine/users/search | 
[**sendFriendRequest**](DefaultApi.md#sendfriendrequest) | **POST** /api/engine/friends/requests | 
[**startGame**](DefaultApi.md#startgame) | **POST** /api/engine/games/{gameId}/start | 
[**submitAction**](DefaultApi.md#submitaction) | **POST** /api/engine/games/{gameId}/action | 
[**unblockUser**](DefaultApi.md#unblockuser) | **DELETE** /api/engine/friends/{userId}/block | 
[**unregisterDevice**](DefaultApi.md#unregisterdevice) | **DELETE** /api/engine/me/devices/{fid} | 
[**updateUsername**](DefaultApi.md#updateusername) | **PUT** /api/engine/me/username | 


# **acceptFriendRequest**
> acceptFriendRequest(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String userId = userId_example; // String | 

try {
    api.acceptFriendRequest(userId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->acceptFriendRequest: $e\n');
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

# **addBot**
> LobbyAccepted addBot(gameId, addBot)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final AddBot addBot = ; // AddBot | 

try {
    final response = api.addBot(gameId, addBot);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->addBot: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **addBot** | [**AddBot**](AddBot.md)|  | 

### Return type

[**LobbyAccepted**](LobbyAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **blockUser**
> blockUser(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String userId = userId_example; // String | 

try {
    api.blockUser(userId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->blockUser: $e\n');
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

# **botAction**
> botAction(botAction)



### Example
```dart
import 'package:eigen_api/api.dart';
// TODO Configure API key authorization: botHmac
//defaultApiClient.getAuthentication<ApiKeyAuth>('botHmac').apiKey = 'YOUR_API_KEY';
// uncomment below to setup prefix (e.g. Bearer) for API key, if needed
//defaultApiClient.getAuthentication<ApiKeyAuth>('botHmac').apiKeyPrefix = 'Bearer';

final api = EigenApi().getDefaultApi();
final BotAction botAction = ; // BotAction | 

try {
    api.botAction(botAction);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->botAction: $e\n');
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

# **cancelGame**
> LobbyAccepted cancelGame(gameId, lobbyCommand)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final LobbyCommand lobbyCommand = ; // LobbyCommand | 

try {
    final response = api.cancelGame(gameId, lobbyCommand);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->cancelGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **lobbyCommand** | [**LobbyCommand**](LobbyCommand.md)|  | 

### Return type

[**LobbyAccepted**](LobbyAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createGame**
> Created createGame(createGame)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final CreateGame createGame = ; // CreateGame | 

try {
    final response = api.createGame(createGame);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->createGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createGame** | [**CreateGame**](CreateGame.md)|  | 

### Return type

[**Created**](Created.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createSoloGame**
> SoloStarted createSoloGame(createSolo)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final CreateSolo createSolo = ; // CreateSolo | 

try {
    final response = api.createSoloGame(createSolo);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->createSoloGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createSolo** | [**CreateSolo**](CreateSolo.md)|  | 

### Return type

[**SoloStarted**](SoloStarted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteAccount**
> deleteAccount()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();

try {
    api.deleteAccount();
} catch on DioException (e) {
    print('Exception when calling DefaultApi->deleteAccount: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **forfeitGame**
> CommandAccepted forfeitGame(gameId, forfeit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final Forfeit forfeit = ; // Forfeit | 

try {
    final response = api.forfeitGame(gameId, forfeit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->forfeitGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **forfeit** | [**Forfeit**](Forfeit.md)|  | 

### Return type

[**CommandAccepted**](CommandAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getBots**
> Bots getBots()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();

try {
    final response = api.getBots();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getBots: $e\n');
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

# **getFrames**
> Frames getFrames(gameId, from, to)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final int from = 56; // int | 
final int to = 56; // int | 

try {
    final response = api.getFrames(gameId, from, to);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getFrames: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **from** | **int**|  | [optional] [default to 0]
 **to** | **int**|  | [optional] 

### Return type

[**Frames**](Frames.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getFriendsGames**
> FriendsGames getFriendsGames(limit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final int limit = 56; // int | 

try {
    final response = api.getFriendsGames(limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getFriendsGames: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **int**|  | [optional] [default to 20]

### Return type

[**FriendsGames**](FriendsGames.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getGame**
> GameSummary getGame(gameId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 

try {
    final response = api.getGame(gameId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 

### Return type

[**GameSummary**](GameSummary.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getLobby**
> Lobby getLobby(limit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final int limit = 56; // int | 

try {
    final response = api.getLobby(limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getLobby: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **int**|  | [optional] [default to 20]

### Return type

[**Lobby**](Lobby.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyGames**
> MyGames getMyGames(bucket, limit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String bucket = bucket_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.getMyGames(bucket, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getMyGames: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bucket** | **String**|  | [optional] [default to 'active']
 **limit** | **int**|  | [optional] [default to 20]

### Return type

[**MyGames**](MyGames.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyRatingHistory**
> RatingHistory getMyRatingHistory(pool, limit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String pool = pool_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.getMyRatingHistory(pool, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getMyRatingHistory: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pool** | **String**|  | [optional] 
 **limit** | **int**|  | [optional] [default to 20]

### Return type

[**RatingHistory**](RatingHistory.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyRatings**
> Ratings getMyRatings()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();

try {
    final response = api.getMyRatings();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getMyRatings: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

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

final api = EigenApi().getDefaultApi();
final String ids = ids_example; // String | 

try {
    final response = api.getPlayers(ids);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getPlayers: $e\n');
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

# **getProfile**
> Profile getProfile()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();

try {
    final response = api.getProfile();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getProfile: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**Profile**](Profile.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **joinGame**
> LobbyAccepted joinGame(gameId, join)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final Join join = ; // Join | 

try {
    final response = api.joinGame(gameId, join);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->joinGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **join** | [**Join**](Join.md)|  | 

### Return type

[**LobbyAccepted**](LobbyAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **joinGameByCode**
> LobbyAccepted joinGameByCode(joinByCode)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final JoinByCode joinByCode = ; // JoinByCode | 

try {
    final response = api.joinGameByCode(joinByCode);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->joinGameByCode: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **joinByCode** | [**JoinByCode**](JoinByCode.md)|  | 

### Return type

[**LobbyAccepted**](LobbyAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **leaveGame**
> LobbyAccepted leaveGame(gameId, lobbyCommand)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final LobbyCommand lobbyCommand = ; // LobbyCommand | 

try {
    final response = api.leaveGame(gameId, lobbyCommand);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->leaveGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **lobbyCommand** | [**LobbyCommand**](LobbyCommand.md)|  | 

### Return type

[**LobbyAccepted**](LobbyAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listFriendRequests**
> FriendRequests listFriendRequests()



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();

try {
    final response = api.listFriendRequests();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->listFriendRequests: $e\n');
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

final api = EigenApi().getDefaultApi();

try {
    final response = api.listFriends();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->listFriends: $e\n');
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

# **registerDevice**
> registerDevice(deviceRegistration)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final DeviceRegistration deviceRegistration = ; // DeviceRegistration | 

try {
    api.registerDevice(deviceRegistration);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->registerDevice: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **deviceRegistration** | [**DeviceRegistration**](DeviceRegistration.md)|  | 

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeFriend**
> removeFriend(userId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String userId = userId_example; // String | 

try {
    api.removeFriend(userId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->removeFriend: $e\n');
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

final api = EigenApi().getDefaultApi();
final String q = q_example; // String | 
final int limit = 56; // int | 

try {
    final response = api.searchUsers(q, limit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->searchUsers: $e\n');
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

final api = EigenApi().getDefaultApi();
final FriendTarget friendTarget = ; // FriendTarget | 

try {
    final response = api.sendFriendRequest(friendTarget);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->sendFriendRequest: $e\n');
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

# **startGame**
> CommandAccepted startGame(gameId, lobbyCommand)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final LobbyCommand lobbyCommand = ; // LobbyCommand | 

try {
    final response = api.startGame(gameId, lobbyCommand);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->startGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **lobbyCommand** | [**LobbyCommand**](LobbyCommand.md)|  | 

### Return type

[**CommandAccepted**](CommandAccepted.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **submitAction**
> CommandAccepted submitAction(gameId, action)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String gameId = gameId_example; // String | 
final Action action = ; // Action | 

try {
    final response = api.submitAction(gameId, action);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->submitAction: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **action** | [**Action**](Action.md)|  | 

### Return type

[**CommandAccepted**](CommandAccepted.md)

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

final api = EigenApi().getDefaultApi();
final String userId = userId_example; // String | 

try {
    api.unblockUser(userId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->unblockUser: $e\n');
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

# **unregisterDevice**
> unregisterDevice(fid)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final String fid = fid_example; // String | 

try {
    api.unregisterDevice(fid);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->unregisterDevice: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **fid** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateUsername**
> UsernameUpdated updateUsername(usernameUpdate)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getDefaultApi();
final UsernameUpdate usernameUpdate = ; // UsernameUpdate | 

try {
    final response = api.updateUsername(usernameUpdate);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->updateUsername: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **usernameUpdate** | [**UsernameUpdate**](UsernameUpdate.md)|  | 

### Return type

[**UsernameUpdated**](UsernameUpdated.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

