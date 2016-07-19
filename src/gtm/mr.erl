-module(mr).
% Created mr.erl the 12:53:48 (07/01/2015) on core
% Last Modification of mr.erl at 11:25:22 (27/09/2015) on core
% 
% This is the Master Registry Module.
% Purpose: query the database.
% Author: "rolph" <rolphin@free.fr>

-export([
    get/1,
    set/2
]).

get(Key) ->
    case db:call(<<"get">>,<<"%mr">>, [ Key ]) of
        {ok, Result} ->
            parse(Result);
        {error, _} = Error ->
            Error
    end.

set(Key,Value) ->
    case db:call(<<"set">>,<<"%mr">>, [ Key, Value ]) of
        {ok, Result} ->
            parse(Result);
        {error, _} = Error ->
            Error
    end.

parse(<<0:8, _/binary>> = Result) ->
    case db_results:unpack(Result) of
        {error, _} = Error ->
            Error;
        Any ->
            Any
    end;
    
parse(Result) ->
    {ok, Result}.
    

