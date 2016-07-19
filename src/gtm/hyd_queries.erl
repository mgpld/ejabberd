-module(hyd_queries).
% Created hyd_queries.erl the 08:01:54 (24/11/2014) on core
% Last Modification of hyd_queries.erl at 01:20:57 (07/02/2015) on core
% 
% Author: "rolph" <rolphin@free.fr>

-export([
    reload/0
]).

-export([
    new/2, new/3,
    query/2, query/4,
    create/2,
    insert/2, insert/3,
    run/3
]).

-define(TEST, true).

-ifdef(TEST).
-export([
    test/0
]).
-endif.

% The module is _reqs.m
module() ->
    <<"%reqs">>.

reload() ->
    hyd:reload( <<"_reqs">> ).

-spec run(
    Ops :: list() ) -> list().

%run(Ops) ->
%    case hyd:call(Ops) of
%        {ok, Results} ->
%            lists:map( fun
%                ({error, _} = Error) ->
%                    Error;
%                (X) ->
%                    case db_results:unpack(X) of
%                        {ok, Result} ->
%                            Result;
%                        {error, _} = Error ->
%                            Error
%                    end
%                end, Results);
%        _ ->
%            []
%    end.

run(Op) ->
    case hyd:call(Op) of
        {ok, Elements } ->
            Results = lists:foldl( fun
                (_, {error, _} = _Acc) ->
                    _Acc;
                ({error, _} = _Error, _) ->
                    _Error;
                (X, Acc) ->
                    case db_results:unpack(X) of
                        {ok, Result} ->
                            [ Result | Acc ];
                        {error, _} = Error ->
                            Error
                    end
                end, [], Elements),
            lists:flatten(Results);
            
        _ ->
            internal_error(74)
    end.

-spec exec(
    Ops :: list() ) -> {ok, list()} | {error, term()}.

exec(Op) ->
    hyd:call([Op]).

-spec create(
    Userid :: non_neg_integer,
    Title :: list() | binary() ) -> list() | error | {error, term()}.

create(Userid,Title) ->
    {_, Offset, _} = os:timestamp(),
    Op = hyd:operation(<<"create">>, module(), [ Offset, Userid, Title ]),
    case exec(Op) of
        {error, _} = _Err ->
            _Err;

        {ok, Data} ->
            case hd(Data) of
                {error, _} = _Err ->
                    _Err;

                <<>> -> % something wrong, propagate
                    error;
                    
                Packed  ->
                    db_results:unpack(Packed)
            end
    end.

-spec new(
    Userid :: non_neg_integer(),
    Params :: list() ) -> list().

new(Userid, [ Title, Args ]) ->
    new(Userid, Title, Args).
    
-spec new(
    Userid :: non_neg_integer(),
    Title :: list() | binary(),
    Values :: list()) -> list().

new(Userid, Title, Values) ->
    case create(Userid,Title) of
        error ->
            internal_error(95);

        {error, _} = _Err ->
            _Err;

        {ok, Id} ->
            case insert(Userid, Id, Values) of
                [] ->
                    internal_error(103, [Id]);

                Positions ->
                    [{<<"id">>, Id}, 
                     {<<"count">>, hd(Positions)}]
            end
    end.

% Associate a query with a name
insert(Userid, Name, Values) when is_list(Values) ->
    Queries = lists:foldl( fun
        ({ _Pos, {struct, Arg}}, Acc) ->
            {Type, Expression} = extract(Arg),
            [ [ Name, Type, Expression ] | Acc ];
            %[ [ Name, Id, Type, Expression ] | Acc ];

        (_, Acc) ->
            Acc

    end, [], Values),
    insert(Userid, Queries).

insert(_Userid, Queries) ->
    lists:foldl( fun
            ( _, {error, _} = Acc) ->
                Acc;
            ( Args, Acc ) ->
                case exec( hyd:operation(<<"addClause">>, module(), Args) ) of
                    {ok, [ Pos ]} ->
                        [ Pos | Acc ];

                    error ->
                        {error, internal_error(136)};

                    {error, _} = _Err ->
                        {error, _Err}
                end
        end, [], Queries).

-spec run(
    Userid :: non_neg_integer(),
    Name :: list() | binary(),
    Type :: list() | binary() ) -> true | false.

run(Userid, Name, Type) ->
    Operation = hyd:operation(<<"run">>, module(), [ Userid, Name, Type ]),
    case exec( Operation ) of
        {ok, [<<"1">>]} -> % there's some results
            true;

        {ok, []} -> % there's no result
            false;

        {error, _Reason} ->
            false
            
    end.

-spec query(
    Userid :: non_neg_integer(),
    Params :: list()
    ) -> list().

query(Userid, [Fqid, Type]) ->
    query(Userid, Fqid, Type, []);

query(Userid, [Fqid, Type | Params ]) ->
    query(Userid, Fqid, Type, Params).
    

-spec query(
    Userid :: non_neg_integer(),
    Fqid :: list() | binary(),
    Type :: list() | binary(),
    Params :: list()
    ) -> list().

query(Userid, Id, Type, Params) ->
    Ops = [ 
        hyd:operation(<<"query">>, module(), [ Userid, Id, Type | Params ]) 
    ],
    case run(Ops) of 
        {ok, Result} ->
            Result;

        _Err ->
            _Err
    end.
    
% internal

extract(Args) ->
    extract( Args, {true, true}).

extract([], Result) ->
    Result;
extract([{<<"type">>, Value} | Rest ], { _, Operation }) ->
    extract(Rest, { Value, Operation});
extract([{<<"operation">>, Value} | Rest ], { Type, _}) ->
    extract(Rest, {Type, Value});
extract([ _ | Rest], Result) ->
    extract( Rest, Result).

internal_error(Code) ->
    hyd:error(?MODULE, Code).

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

-ifdef(TEST).
test() ->
    Args = [
        {<<"1">>,{struct,[
            {<<"type">>,<<"and">>},
            {<<"operation">>,<<"title !">>}]}},
        {<<"2">>,{struct,[
            {<<"type">>,<<"and">>},
            {<<"operation">>,<<"owner == 1001">>}]}},
        {<<"3">>,{struct,[
            {<<"type">>,<<"or">>},
            {<<"operation">>,<<"title %like% group">>}]}
        }],

    Userid = 1001,
    Name = <<"abc">>,
    new(Userid, Name, Args).
    %insert(Userid, Name, Args).

-endif.
