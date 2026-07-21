# eigen_api.api.GamesApi

## Load the API package
```dart
import 'package:eigen_api/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addBot**](GamesApi.md#addbot) | **POST** /api/engine/games/{gameId}/add-bot | 
[**cancelGame**](GamesApi.md#cancelgame) | **POST** /api/engine/games/{gameId}/cancel | 
[**createGame**](GamesApi.md#creategame) | **POST** /api/engine/games | 
[**createSoloGame**](GamesApi.md#createsologame) | **POST** /api/engine/games/solo | 
[**forfeitGame**](GamesApi.md#forfeitgame) | **POST** /api/engine/games/{gameId}/forfeit | 
[**getFrames**](GamesApi.md#getframes) | **GET** /api/engine/games/{gameId}/frames | 
[**getGame**](GamesApi.md#getgame) | **GET** /api/engine/games/{gameId} | 
[**getLobby**](GamesApi.md#getlobby) | **GET** /api/engine/lobby | 
[**getMyGames**](GamesApi.md#getmygames) | **GET** /api/engine/games/mine | 
[**joinGame**](GamesApi.md#joingame) | **POST** /api/engine/games/{gameId}/join | 
[**joinGameByCode**](GamesApi.md#joingamebycode) | **POST** /api/engine/games/join-by-code | 
[**leaveGame**](GamesApi.md#leavegame) | **POST** /api/engine/games/{gameId}/leave | 
[**startGame**](GamesApi.md#startgame) | **POST** /api/engine/games/{gameId}/start | 
[**submitAction**](GamesApi.md#submitaction) | **POST** /api/engine/games/{gameId}/action | 


# **addBot**
> LobbyAccepted addBot(gameId, addBot)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final AddBot addBot = ; // AddBot | 

try {
    final response = api.addBot(gameId, addBot);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->addBot: $e\n');
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

# **cancelGame**
> LobbyAccepted cancelGame(gameId, lobbyCommand)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final LobbyCommand lobbyCommand = ; // LobbyCommand | 

try {
    final response = api.cancelGame(gameId, lobbyCommand);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->cancelGame: $e\n');
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

final api = EigenApi().getGamesApi();
final CreateGame createGame = ; // CreateGame | 

try {
    final response = api.createGame(createGame);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->createGame: $e\n');
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

final api = EigenApi().getGamesApi();
final CreateSolo createSolo = ; // CreateSolo | 

try {
    final response = api.createSoloGame(createSolo);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->createSoloGame: $e\n');
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

# **forfeitGame**
> CommandAccepted forfeitGame(gameId, forfeit)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final Forfeit forfeit = ; // Forfeit | 

try {
    final response = api.forfeitGame(gameId, forfeit);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->forfeitGame: $e\n');
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

# **getFrames**
> Frames getFrames(gameId, from, to)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final int from = 56; // int | 
final int to = 56; // int | 

try {
    final response = api.getFrames(gameId, from, to);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->getFrames: $e\n');
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

# **getGame**
> GameSummary getGame(gameId)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 

try {
    final response = api.getGame(gameId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->getGame: $e\n');
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
> Lobby getLobby(limit, cursor)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final int limit = 56; // int | 
final int cursor = 56; // int | 

try {
    final response = api.getLobby(limit, cursor);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->getLobby: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **limit** | **int**|  | [optional] [default to 20]
 **cursor** | **int**|  | [optional] 

### Return type

[**Lobby**](Lobby.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyGames**
> MyGames getMyGames(bucket, limit, cursor)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String bucket = bucket_example; // String | 
final int limit = 56; // int | 
final int cursor = 56; // int | 

try {
    final response = api.getMyGames(bucket, limit, cursor);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->getMyGames: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bucket** | **String**|  | [optional] [default to 'active']
 **limit** | **int**|  | [optional] [default to 20]
 **cursor** | **int**|  | [optional] 

### Return type

[**MyGames**](MyGames.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **joinGame**
> Joined joinGame(gameId, join)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final Join join = ; // Join | 

try {
    final response = api.joinGame(gameId, join);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->joinGame: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **gameId** | **String**|  | 
 **join** | [**Join**](Join.md)|  | 

### Return type

[**Joined**](Joined.md)

### Authorization

[firebase](../README.md#firebase)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **joinGameByCode**
> Joined joinGameByCode(joinByCode)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final JoinByCode joinByCode = ; // JoinByCode | 

try {
    final response = api.joinGameByCode(joinByCode);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->joinGameByCode: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **joinByCode** | [**JoinByCode**](JoinByCode.md)|  | 

### Return type

[**Joined**](Joined.md)

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

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final LobbyCommand lobbyCommand = ; // LobbyCommand | 

try {
    final response = api.leaveGame(gameId, lobbyCommand);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->leaveGame: $e\n');
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

# **startGame**
> CommandAccepted startGame(gameId, lobbyCommand)



### Example
```dart
import 'package:eigen_api/api.dart';

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final LobbyCommand lobbyCommand = ; // LobbyCommand | 

try {
    final response = api.startGame(gameId, lobbyCommand);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->startGame: $e\n');
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

final api = EigenApi().getGamesApi();
final String gameId = gameId_example; // String | 
final Action action = ; // Action | 

try {
    final response = api.submitAction(gameId, action);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GamesApi->submitAction: $e\n');
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

