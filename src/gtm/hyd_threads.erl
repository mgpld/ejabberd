-module(hyd_threads).
% Created hyd_threads.erl the 06:02:15 (24/09/2014) on core
% Last Modification of hyd_threads.erl at 16:26:41 (19/10/2014) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    reload/0
]).

-export([
    add/2,
    del/2,
    bounds/1,
    create/2,
    subscribe/2, 
    unsubscribe/2,
    subscribers/1
]).

-ifdef(debug).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

module() ->
    <<"threads">>.

reload() ->
    hyd:reload( module() ).
	
%% Borrowed from hyd_users
run(Ops) when length(Ops) > 1 ->
    case hyd:call(Ops) of
        {ok, Results} ->
            lists:map( fun
                ({error, _} = Error) ->
                    Error;
                (X) ->
                    db_results:unpack(X)
                end, Results);
        _ ->
            []
        end;

run(Ops) ->
    case hyd:call(Ops) of
        {ok, [<<>>]} ->
            [];

        {ok, [{error, _} = Error]} ->
            Error;

        {ok, [Result]} ->
            db_results:unpack(Result);

        _ ->
            []
    end.

% Create a thread
create(Shard, Owner) ->
    Ops = [
        hyd:operation(<<"create">>, module(), [ Shard, Owner ])
    ],
    case hyd:call(Ops) of
        {ok, [Threadid]} ->  
            {ok, Threadid};

        [<<"0">>] ->
            {error, enotsup};

        _ ->
            []
    end.
    
% Subscribe an user to a thread
subscribe(Threadid, User) ->
    Ops = [
        hyd:operation(<<"subscribe">>, module(), [ Threadid, User ]) 
    ],
    run(Ops).

% Unsubscribe an user to a thread
unsubscribe(Threadid, User) ->
    Ops = [
        hyd:operation(<<"unsubscribe">>, module(), [ Threadid, User ]) 
    ],
    run(Ops).

% Retrieve the subscribers
-spec subscribers(
    Threadid :: non_neg_integer() ) -> [term(),...]|[].

subscribers(Threadid) ->
    Ops = [
        hyd:operation(<<"subscribers">>, module(), [ Threadid ])
    ],
    run(Ops).

% Returns the count, the first and the last msgid of this thread
bounds(Threadid) ->
    Ops = [
        hyd:operation(<<"bounds">>, module(), [ Threadid ])
    ],
    run(Ops).

add(Threadid, Msgid) ->
    Ops = [
        hyd:operation(<<"add">>, module(), [ Threadid, Msgid ])
    ], 
    run(Ops).

del(Threadid, Msgid) ->
    Ops = [
        hyd:operation(<<"del">>, module(), [ Threadid, Msgid ])
    ],
    run(Ops).
