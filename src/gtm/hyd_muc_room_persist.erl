-module(hyd_muc_room_persist).
% Created hyd_muc_room_persist.erl the 02:14:53 (06/02/2014) on core
% Last Modification of hyd_muc_room_persist.erl at 17:37:40 (23/09/2014) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    log/1, log/4,
    subscribe/2, unsubscribe/2, subscribers/1
]).

-ifdef(TEST).
-export([
    test/0
]).
-endif.

-define(REALMODULE, hyd_messages).

-spec log(
    Message :: term() ) -> ok.

log(Message) ->
    Ops = [
    	"log"
    ],
    [ Id, From, To] = get_message_info(Message),
    hyd:call(Ops, [Id, From, To]).

-spec log(
    Threadid :: list() | binary(),
    Msgid :: list() | binary(),
    From :: binary(),
    Content :: list() ) -> ok.

log(Threadid, Msgid, From, Content) ->
    ?REALMODULE:add(Threadid, Msgid, From, Content).

% Subscribe an user
-spec subscribe(
    Threadid :: list() | binary() | non_neg_integer(),
    User :: list() | binary() ) -> {ok, [list()]}.

subscribe( Threadid, User ) ->
    ?REALMODULE:subscribe( Threadid, User ).
    
% Unsubscribe an user
-spec unsubscribe(
    Threadid :: list() | binary() | non_neg_integer(),
    User :: list() | binary() ) -> {ok, [list()]}.

unsubscribe( Threadid, User ) ->
    ?REALMODULE:unsubscribe( Threadid, User ).

-spec subscribers(
    Threadid :: list() | binary() | non_neg_integer() ) -> [] | [binary(),...].

subscribers( Threadid ) ->
    ?REALMODULE:subscribers( Threadid ).

get_message_info(Message) when is_tuple(Message) ->
    From = element(2, Message),
    To = element(3, Message),
    Id = element(4, Message),
    [ Id, From, To ];
get_message_info(_) ->
    {error, invalid}.

-ifdef(TEST).
test() ->
    Message = {message, <<"From">>, <<"To">>, <<"Id">>, <<"Body">>},
    log(Message).
-endif.
