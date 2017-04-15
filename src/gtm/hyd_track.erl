-module(hyd_track).
% Created hyd_track.erl the 11:58:52 (01/04/2017) on core
% Last Modification of hyd_track.erl at 05:31:55 (15/04/2017) on core
% 
% Author: "ak" <ak@harmonygroup.net>

-export([
    async/5,
    reload/0
]).

-export([
    get/3,
    info/3,
    record/3,
    reset/3,
    track/3,
    total/3
]).

-export([
    data/0
]).

-include("logger.hrl").

module() ->
    <<"track">>.

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

info(User, SeqId, [ _Id, _Data ] = Params) ->
    Pid = self(),
    spawn( ?MODULE, async, [ SeqId, Pid, <<"track">>, <<"info">>, [ User | Params ]]).

track(User, SeqId, Params) ->
    Pid = self(),
    spawn( ?MODULE, async, [ SeqId, Pid, <<"track">>, <<"track">>, [ User | Params ]]).

record(User, SeqId, Params) ->
    Pid = self(),
    spawn( ?MODULE, async, [ SeqId, Pid, <<"track">>, <<"record">>, [ User | Params ]]).

get(User, SeqId, _Args) ->
    empty(User, SeqId).

total(User, SeqId, Params) ->
    Pid = self(),
    spawn( ?MODULE, async, [ SeqId, Pid, <<"track">>, <<"total">>, [ User | Params ]]).

reset(User, SeqId, [ _Id, _Institution ] = Params ) ->
    Pid = self(),
    spawn( ?MODULE, async, [ SeqId, Pid, <<"track">>, <<"reset">>, [ User | Params ]]);

reset(User, SeqId, _Args) ->
    empty(User, SeqId).


% internals
empty(User, SeqId) ->
    Me = self(),
    Me ! {async, SeqId, [<<>>]}.

async(SeqId, Pid, Element, <<"reset">>, [ User, Lesson, Data ]) ->
    Result = reset(SeqId, User, Lesson, Data),
    async_response(SeqId, Pid, Result);
    
async(SeqId, Pid, Element, <<"record">>, [ User, Lesson, Data ]) ->
    Result = record(SeqId, User, Lesson, Data),
    async_response(SeqId, Pid, Result);

async(SeqId, Pid, Element, <<"info">>, [ User, Id, Data ]) ->
    Result = info(SeqId, User, Id, Data),
    ?DEBUG("async: result: ~p", [ Result ]),
    async_response(SeqId, Pid, Result);

async(SeqId, Pid, Element, <<"total">>, [ User, Id, Total ]) ->
    Result = total(SeqId, User, Id, Total),
    ?DEBUG("async: result: ~p", [ Result ]),
    async_response(SeqId, Pid, Result);

async(SeqId, Pid, Element, Operation, Params) ->
    hyd_fqids:action_async(SeqId, Element, Operation, Params),
    receive 
        {db, SeqId, _} = Packet ->
            Pid ! setelement(1, Packet, async);
        _ ->
            Pid ! {async, SeqId, [<<>>]}

    after 100000 ->
            Pid ! {async, SeqId, [<<>>]}
    end.

async_response(SeqId, Pid, Result) ->
    case Result of
        {ok, []} = Response ->
            Pid ! {async, SeqId, {ok, [<<>>]}}; 
        {ok, Response} ->
            Pid ! {async, SeqId, Response};
        {error, _} = _Error ->
            Pid ! {async, SeqId, _Error}
    end.

% Info call
info(SeqId, User, Id, {struct, Items}) ->
    do_info(SeqId, User, Id, Items, []).

do_info(_SeqId, _User, _Id, [], [[Result]]) ->
    ?DEBUG("do_info: final result: ~p", [ Result ]),
    {ok, {ok, Result}};
do_info(_SeqId, _User, _Id, [], Result) ->
    ?DEBUG("do_info: final result: ~p", [ Result ]),
    {ok, {ok, Result}};
do_info(SeqId, User, Id, [{<<"totalSlide">>, Slides} | Rest], Result) ->
    ?DEBUG("do_info: totalSlide result: ~p", [ Result ]),
    db(SeqId, User, <<"track">>, <<"total">>, [ Id, Slides ], undefined),
    do_info(SeqId, User, Id, Rest, Result);
do_info(SeqId, User, Id, [{Section, Items} | Rest], Result) ->
    ?DEBUG("do_info: Section result: ~p", [ Result ]),
    Success = leaf(SeqId, User, Id, Section, Items, Result),
    ?DEBUG("do_info: result: ~p", [ Success ]),
    do_info(SeqId, User, Id, Rest, Success);
do_info(SeqId, User, Id, [ _ | Rest ], Result) ->
    ?DEBUG("do_info: default result: ~p", [ Result ]),
    do_info(SeqId, User, Id, Rest, Result).


leaf(SeqId, User, Id, Name, {struct, Items}, Result) ->
    lists:foldl(fun({I, {struct, Ids}}, _Acc) ->
        case insert(SeqId, User, Id, Name, I, Ids, Result) of
            [] -> 
                _Acc;
            _Any ->
                [ _Any | _Acc ]
        end
    end, Result, Items).

insert(SeqId, User, Institution, Name, I, Ids, Result) ->
    lists:foldl(fun({J, Id}, Acc) ->
        NewResult = db(SeqId, User, <<"track">>, <<"store">>, [ Institution, Name, I, J, Id ], Result),
        io:format("SeqId: ~p, User: ~p, Id: ~p, Name: ~p[~p][~p] = ~p\nResult: ~p\n", [ SeqId, User, Institution, Name, I, J, Id, NewResult ]),
        case NewResult of
            {ok, <<"t">>} ->
                Acc;
            {ok, _Any} ->
                [ _Any | Acc ];
            _ ->
                Acc
        end
    end, [], Ids).

%run(Type, <<"store">>, SeqId, User, Institution, Name, I, Ids, Result) 
%run(Type, Operation, SeqId, User, Params, Result)

run(record, SeqId, User, Lesson, Section, {struct, Items}, Result) ->
    lists:foldl(fun({ItemId, {struct, Answers}}, _Acc0) ->
        lists:foldl(fun({Id, Answer}, _Acc1) ->
            ?DEBUG("run(record): SeqId: ~p, User: ~p, Lesson: ~p, Section: ~p ItemId: ~p Id: ~p Answer: ~p\n", [ 
                SeqId, User, Lesson, Section, ItemId, Id, Answer ]),
            db(SeqId, User, <<"track">>, <<"record">>, [ Lesson, Section, ItemId, Id, Answer ], Result)
        end, [], Answers)
    end, 0, Items);

run(reset, SeqId, User, Lesson, Section, Items, Result) ->
    lists:foldl(fun(ItemId, Acc) ->
        NewAcc = db(SeqId, User, <<"track">>, <<"reset">>, [ Lesson, Section, ItemId ], Acc),
        ?DEBUG("run(reset): SeqId: ~p, User: ~p, Lesson: ~p, Section: ~p ItemId: ~p, result: ~p\n", [ 
            SeqId, User, Lesson, Section, ItemId, NewAcc ]),
        NewAcc
    end, Result, Items);

run(_, _SeqId, _User, _Id, _Section, _Items, _Result) ->
    ok.

% Record call
record(SeqId, User, Lesson, {struct, Items}) ->
    do_record(SeqId, User, Lesson, Items, 0).

do_record(_SeqId, _User, _Lesson, [], Result) ->
    {ok, Result};
do_record(SeqId, User, Lesson, [{Section, Items} | Rest], Result) ->
    Success = run(record, SeqId, User, Lesson, Section, Items, Result),
    do_record(SeqId, User, Lesson, Rest, Success).

% Reset call
reset(SeqId, User, Lesson, {struct, Items}) ->
    do_reset(SeqId, User, Lesson, Items, 0).

do_reset(_SeqId, _User, _Lesson, [], Result) ->
    {ok, Result};
do_reset(SeqId, User, Lesson, [{Section, Items} | Rest], Result) ->
    Success = run(reset, SeqId, User, Lesson, Section, Items, Result),
    do_reset(SeqId, User, Lesson, Rest, Success).

% Total call
total(SeqId, User, Lesson, Total) ->
    db(SeqId, User, <<"track">>, <<"total">>, [ Lesson, Total ], []).

% db async call
db(SeqId, User, Element, Operation, Args, Count) ->
    hyd_fqids:action_async(SeqId, Element, Operation, [ User | Args]),
    receive 
        {db, SeqId, Result} = Packet ->
            case Result of
                {ok, Response} ->
                    ?DEBUG("db: packet: ~p", [ Packet ]),
                    case db_results:unpack(Response) of
                        {error, Reason} = _Error ->
                            ?DEBUG("error: ~p", [ Reason ]),
                            _Error;
                            
                        {ok, Answer} = _Ok ->
                            ?DEBUG("answer: ~p", [ Answer ]),
                            _Ok;

                        {ok, Infos, More} ->
                            case db_results:unpack(More) of
                                {error, Reason} = _Error ->
                                    ?DEBUG("error: ~p", [ Reason ]),
                                    _Error;
                            
                                {ok, Answer} = _Ok ->
                                    ?DEBUG("answer: ~p", [ Answer ]),
                                    _Ok
                            end
                    end;

                {error, Reason} = _Error ->
                    ?DEBUG("error: ~p", [ Reason ]),
                    _Error
            end
            
    after 1000 ->
        Count
    end.

data() ->
    {ok,{struct,[{<<"activities">>,
              {struct,[{<<"1">>,
                        {struct,[{<<"1">>,<<"586d9bbd3a1fd309fba70ce5">>}]}},
                       {<<"2">>,
                        {struct,[{<<"1">>,<<"586da5de3a1fd309fba70ce7">>},
                                 {<<"2">>,<<"586e0e6d59302e1f81768454">>},
                                 {<<"3">>,<<"586e0e8759302e1f81768455">>}]}}]}},
             {<<"exercices">>,
              {struct,[{<<"1">>,
                        {struct,[{<<"1">>,<<"586e0e8759302e1f81768455">>},
                                 {<<"2">>,<<"586da5de3a1fd309fba70ce7">>}]}},
                       {<<"2">>,
                        {struct,[{<<"1">>,<<"586e0e6d59302e1f81768454">>},
                                 {<<"2">>,<<"586d9bbd3a1fd309fba70ce5">>}]}}]}}]}}.

