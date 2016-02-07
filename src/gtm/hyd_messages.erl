-module(hyd_messages).
% Created hyd_messages.erl the 14:27:44 (05/04/2014) on core
% Last Modification of hyd_messages.erl at 06:10:55 (24/09/2014) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    reload/0
]).

-export([
    get/1, get/2,
    content/2,
    bounds/1,
    add/4,
    del/2
]).


-export([
    all/1, all/2,
    childs/2, childs/3,
    childs_values/2
]).

-export([
    count/1,
    search/2,
    words_tree/1
]).

-export([
    subscribe/2, 
    unsubscribe/2,
    subscribers/1
]).

-export([
    search/2, search/3,
    search_exact/2, search_exact/3
]).

-define(MESSAGES_MODULE, "^messages").

-ifdef(debug).
-export([
    unpack_test/0
]).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

module() ->
    <<"messages">>.

reload() ->
    hyd:reload( module() ).

-spec all( 
    UserId :: non_neg_integer(),
    Subscripts :: list() ) -> list().

all(UserId, Subscripts) ->
    Args = gtmproxy_fmt:ref(Subscripts),
    Ops = [
        hyd:operation(<<"childs">>, module(), [ UserId, Args ])
    ],
    run(Ops).

childs(UserId,Subscripts) ->
    Fun = fun(X) ->
        X
    end,
    childs(UserId,Subscripts,Fun).

childs(Root,Subscripts,Fun) ->
    Subs = Subscripts ++ ["items"],
    foreach(Root,Subs,Fun).
    
foreach(Root,Subs) ->
    Fun = fun(X) ->
        lists:last(X)
    end,
    foreach(Root,Subs,Fun).

foreach(UserId,Subscripts,Fun) ->
    Args = gtmproxy_fmt:ref(Subscripts),
    Ops = [
        hyd:operation(<<"childs">>, module(), [ UserId, Args ])
    ],
    case hyd:call(Ops) of
        {ok, [Results]} ->  % One Op means One result
        %Results = db_results:unpack(Packed),
        lists:map( fun(X) ->
                %io:format("--> ~p\n", [ X ]),
                Fun( X )
                end, db_results:unpack(Results) );

        [<<"0">>] ->
            [];

        _ ->
            []
    end.

childs_values(UserId, Subscripts) ->
    Args = gtmproxy_fmt:ref(Subscripts),
    Ops = [
        hyd:operation(<<"childsKV">>, module(), [ UserId, Args ])
    ],
    run(Ops).

%% API
add(Threadid, Msgid, From, Content) ->
    FilteredContent = hyd:quote(Content),
    Ops = [
        hyd:operation(<<"add">>, module(), [ Threadid, Msgid, From, FilteredContent ])
    ], 
    run(Ops).

del(Threadid, Msgid) ->
    Ops = [
        hyd:operation(<<"del">>, module(), [ Threadid, Msgid ])
    ],
    run(Ops).

search(Threadid, Word) ->
    Ops = [
        hyd:operation(<<"search">>, module(), [ Threadid, Word ])
    ], 
    run(Ops).

search(Threadid, Word, Info) ->
    Ops = [
        hyd:operation(<<"search">>, module(), [ Threadid, Word, Info ])
    ],
    run(Ops).

search_exact(Threadid, Word) ->
    Ops = [
        hyd:operation(<<"searchExact">>, module(), [ Threadid, Word ])
    ],
    run(Ops).

search_exact(Threadid, Word, Info) ->
    Ops = [
        hyd:operation(<<"searchExact">>, module(), [ Threadid, Word, Info ])
    ],
    run(Ops).

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

% Retrieve a thread

-spec get(
    Threadid :: non_neg_integer() ) -> [term(),...]|[].

get(Threadid) ->
    childs(Threadid, []).

%    Fun = fun(Msg) ->
%	%io:format("---> ~p\n", [ Profile ]),
%	{Msg, read(Threadid, ["items","profiles",Profile, Key])}
%    end,
%    foreach(UserId,[?CONF_PROP,"profiles"], Fun).
%    Root = ?MESSAGES_MODULE ++ shard(Threadid),
%    Childs = childs( Root, [Threadid], fun( X ) ->
%	Msgid = lists:last(X),
%	[{<<"msgid">>, list_to_integer(Msgid) } | iget( Threadid, Msgid ) ]
%    end),
%    ?DEBUG("Threadid: ~p\n~p", [ Threadid, Childs ]),
%    Childs.

% Retrieve the subscribers
-spec subscribers(
    Threadid :: non_neg_integer() ) -> [term(),...]|[].

subscribers(Threadid) ->
    Ops = [
        hyd:operation(<<"subscribers">>, module(), [ Threadid ])
    ],
    run(Ops).

% Retrieve a msgid from a threadid: OK
-spec get(
    Threadid :: non_neg_integer(),
    Msgid :: non_neg_integer() ) -> [{binary(), binary()},...] | [].

get(Threadid,Msgid) ->
    % childs_values(Threadid, [ "items", Msgid ]).
    Ops = [
        hyd:operation(<<"get">>, module(), [ Threadid, Msgid ]),
        hyd:operation(<<"content">>, module(), [ Threadid, Msgid ])
    ],
    [ [ {Size, Content} ], KVs ] = run(Ops), % order is reversed
    [ {<<"content">>, hyd:unquote(Content)} | KVs ]. % unquote and add the result

content(Threadid, Msgid) ->
    Ops = [
        hyd:operation(<<"content">>, module(), [ Threadid, Msgid ])
    ],
    run(Ops).

% Returns the count, the first and the last msgid of this thread
bounds(Threadid) ->
    Ops = [
        hyd:operation(<<"bounds">>, module(), [ Threadid ])
    ],
    run(Ops).

% Retrieve all threadid ids
-spec all(
    Threadid :: non_neg_integer() ) -> [binary(),...] | [].

all(Threadid) ->
    all(Threadid, []).

% Retrieve a specific threadid subscript for all threadid returning the value with each threadids
% ex: hyd_messages:all(Threadid, []). <-- returns the value
% ex: hyd_messages:all(Threadid, ["author"]).
% ex: hyd_messages:all(Threadid, ["content"]).
% -spec all(
%     Threadid :: non_neg_integer(),
%     Subscripts :: list()) -> [{binary(), binary()},...] | [].


% internals
read(UserId, Subscripts) ->
    io:format("Accessing: ~p(~p)\n", [ UserId, Subscripts ]),
    Args = gtmproxy_fmt:ref(Subscripts),
    Op = hyd:operation(<<"read">>, module(), [ UserId, Args ]),
    run([ Op ]).

write(UserId, Subscripts, Value) ->
    io:format("Writing: ~p(~p)\n", [ UserId, Subscripts ]),
    Args = gtmproxy_fmt:ref(Subscripts),
    Op = hyd:operation(<<"write">>, module(), [ UserId, Args, Value ]),
    run([ Op ]).

% Returns the number of message in this thread
-spec count(
    Id :: non_neg_integer() ) -> binary().

count(Id) ->
    read(Id, ["count"]).

% Returns the words list and their respective count occurence
% Could be used as Cloug Tag ?
-spec words_tree(
    Id :: non_neg_integer() ) -> [{binary(), binary()},...] | [].

words_tree(Id) ->
    Fun = fun(X) ->
        io:format("D: ~p\n", [ X ])
    end,
    childs(Id, ["stats"], Fun).

unpack(Data) ->
    ?DEBUG("Unpacking ~p ", [ Data ]),
    unpack(Data, undefined, []).

unpack(<<Count:16,1,Rest/binary>>, undefined, Result) ->
    unpack(1, Rest, Count, Result);

unpack(<<Count:16,2,Rest/binary>>, undefined, Result) ->
    unpack(2, Rest, Count, Result).

% Type: 1 Key
unpack(1, <<KS:16,Key:KS/binary,Rest/binary>>, Count, Result) ->
    unpack(1, Rest, Count - 1, [ Key | Result ]);

% Type: 2 Key Value
unpack(2, <<KS:16,Key:KS/binary,VS:16,Value:VS/binary,Rest/binary>>, Count, Result) ->
    unpack(2, Rest, Count - 1, [ {Key, Value} | Result]);

unpack(_, <<>>, Count, Result) ->
    ?DEBUG("End of stream: count: ~p\n", [ Count ]),
    Result;

unpack(_, _, 0, Result) ->
    Result.

%% unpack([ A, B, C, $: | Rest ], undefined, Result) ->
%%     Elems = list_to_integer( [ A, B, C ], 16),
%%     unpack(Rest, Elems, Result);
%% unpack([ A, B, C | Rest ], Elems, [{Key, undefined} | Result]) ->
%%     Count = list_to_integer([ A, B, C ], 16),
%%     {Value, NewRest} = lists:split( Count, Rest ),
%%     unpack(NewRest, Elems - 1, [{Key, list_to_binary(Value)} | Result ]);
%% unpack([ A, B, C | Rest ], Elems, Result) ->
%%     ?DEBUG("Round ~p: Rest: ~p", [ Elems, Rest ]),
%%     Count = list_to_integer([ A, B, C], 16),
%%     {Key, NewRest} = lists:split( Count, Rest ),
%%     unpack(NewRest, Elems, [{list_to_binary(Key), undefined} | Result ]);
%% unpack(_, 0, Result) ->
%%     ?DEBUG("Ended: ~p", [ Result ]),
%%     Result;
%% unpack([], Elems, Result) ->
%%     ?DEBUG("Stream ended at element: ~p", [ Elems ]),
%%     Result;
%% unpack([ What | Rest ], Elems, Result ) ->
%%     ?DEBUG("Unhandled byte: ~p at elems: ~p", [ What, Elems ]),
%%     unpack(Rest, Elems, Result).

%unpack(<<Count:3/binary,":",Rest/binary>>, undefined, Result) ->
%    Elems = list_to_integer( binary_to_list(Count), 10),
%    unpack(Rest, Elems, Result);
%unpack(<<Size:3/binary,Rest/binary>>, Elems, [{Key, undefined} | Result]) ->
%    Count = list_to_integer( binary_to_list(Size), 16),
%    {Value, NewRest} = binary:split( Rest, Count ),
%    unpack(NewRest, Elems - 1, [{Key, Value} | Result ]);
%unpack(<<Size:3/binary,Rest/binary>>, Elems, Result) ->
%    Count = list_to_integer( binary_to_list(Size), 16),
%    {Key, NewRest} = binary:split( Rest, Count ),
%    unpack(NewRest, Elems, [{Key, undefined} | Result ]);
%unpack(_, 0, Result) ->
%    ?DEBUG("Ended: ~p", [ Result ]),
%    Result;
%unpack(<<>>, Elems, Result) ->
%    ?DEBUG("Stream eneded at element: ~p", [ Elems ]),
%    Result;
%unpack(<<What:1/binary,Rest/binary>>, Elems, Result ) ->
%    ?DEBUG("Unhandled byte: ~p at elems: ~p", [ What, Elems ]),
%    unpack(Rest, Elems, Result).
    

unpack_test() ->
%    Data = <<"2:006author008Auteur A005value027Cet apres midi est donc libre pour vous">>,
    Data = "002:006author008Auteur A005value027Cet apres midi est donc libre pour vous",
    unpack(Data).


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
