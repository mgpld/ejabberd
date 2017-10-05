%% Created hyd_fqids.erl the 02:14:53 (06/02/2014) on core
%% Last Modification of hyd_fqids.erl at 09:50:30 (10/06/2017) on core
%% 
%% @author rolph <rolphin@free.fr>
%% @doc Handle interactions with Fqids.

-module(hyd_fqids).

-export([
    reload/0
]).

-export([
    read/1, read/2,
    args/2, args/3,
    stats/1, stats/2,
    valid/1,
    action/3,
    action_async/4
]).

-include("logger.hrl").

-ifdef(TEST).
-export([
    test/0
]).
-endif.

module() ->
    <<"fqids">>.

%% @doc Reload this backend API engine module.
%% Reload itself...

-spec reload() -> ok.
reload() ->
    hyd:reload( module() ).

%% @doc Re information about an fqid.
%% Calling the underlying API engine to do the heavy work.
%% The Userid is needed since viewing informations of a Fqid depends on
%% the viewer (i.e. userid)
-spec read(
    Fqid :: list() | binary(),
    Userid :: list() | binary() ) -> {ok, list()} | {error, term()}.

read(Fqid, Userid) ->
    case correct([Fqid, Userid]) of
        true ->
            do_read(Fqid, Userid);

        false ->
            internal_error(51)
    end.

do_read(Fqid, Userid) ->
    Ops = [
        hyd:operation(<<"read">>, module(), [ Fqid, Userid ])
    ],
    run(Ops).

-spec read(
    Fqid :: list() | binary()) -> {ok, list()} | {error, term()}.

read(Fqid) ->
    case correct([Fqid]) of
        true ->
            do_read(Fqid);

        false ->
            internal_error(72)
    end.

do_read(Fqid) ->
    Ops = [
        hyd:operation(<<"read">>, module(), [ Fqid ])
    ],
    run(Ops).

-spec stats(
    Fqid :: list() | binary()) -> {ok, list()} | {error, term()}.

stats(Fqid) ->
    case correct([Fqid]) of
        true ->
            do_stats(Fqid);

        false ->
            internal_error(88)
    end.

do_stats(Fqid) ->
    Ops = [
        hyd:operation(<<"stats">>, module(), [ Fqid ])
    ],
    run(Ops).

-spec stats(
    Fqid :: list() | binary(),
    Userid :: list() | binary() ) -> {ok, list()} | {error, term()}.

stats(Fqid, Userid) ->
    case correct([Fqid, Userid]) of
        true ->
            do_stats(Fqid, Userid);

        false ->
            internal_error(107)
    end.

do_stats(Fqid, Userid) ->
    Ops = [
        hyd:operation(<<"stats">>, module(), [ Fqid, Userid ])
    ],
    run(Ops).

%% @doc Extract how many arguments the Method of Type call need.
%% Check if Method and Type are first valid identifiers, then if ok
%% perform the call to retrieve the arguments count.
%%
%% If the Type or Method are invalid, returns an error
-spec args(
    Type :: list() | binary(),
    Method :: list() | binary()) -> {ok, list()} | {error, term()}.

args(Type, Method) ->
    case correct([Type, Method]) of
        true ->
            do_args(Type, Method);

        false ->
            internal_error(129)
    end.

%% @doc Perform the actual API call to retrieve arguments count.

do_args(Type, Method) ->
    Ops = [
        hyd:operation(<<"actionArgs">>, module(), [ Type, Method ], 500)
    ],
    run(Ops).
    %parse_singleton(Ops).

-spec args(
    Type :: list() | binary(),
    Method :: list() | binary(),
    Userid :: list() | binary() ) -> list() | {error, term()}.

args(Type, Method, Userid) ->
    case correct([Type, Method, Userid]) of
        true ->
            do_args(Type, Method, Userid);

        false ->
            internal_error(147)
    end.

do_args(Type, <<"create">> = Method, Userid) ->
    Ops = [
        hyd:operation(<<"createArgs">>, module(), [ Type, Method, Userid ])
    ],
    case parse_indexed(Ops) of
        {ok, Result} ->
            Result;
        _Err ->
            _Err
    end;

do_args(Type, Method, Userid) ->
    Ops = [
        hyd:operation(<<"actionArgs">>, module(), [ Type, Method, Userid ], 500)
    ],
    case parse_indexed(Ops) of
        {ok, Result} ->
            Result;
        _Err ->
            _Err
    end.

%% @doc Action on specific fqids.
%% If action is "create", create a new instance of Type.
%% Note: Fqid in this case is a type i.e. "message", or, "photo".
-spec action(
    Type :: list() | binary(),
    Action :: list() | binary(),
    Args :: list() ) -> list() | binary() | {error, term()}. 

action(Type, Method, Args) ->
    case correct([Type, Method, Args]) of
        true ->
            do_action(Type, Method, Args);

        false ->
            internal_error(186)
    end.

do_action(Type, <<"create">>, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    Op = [
        hyd:operation(<<"create">>, module(), [ Type | FilteredArgs ])
    ],
    case parse_singleton(Op) of
        {ok, Result} ->
            Result;
        _Err ->
            _Err
    end;

do_action(Any, Action, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    Op = [
        hyd:operation(<<"action">>, module(), [ Any, Action | FilteredArgs ])
    ],
    run(Op).

%% @doc Asynchronous version of action.
action_async(TransId, Type, Method, Args) ->
    case correct([Type, Method, Args]) of
        true ->
            do_action_async(TransId, Type, Method, Args);

        false ->
            internal_error(216)
    end.

do_action_async(TransId, Type, <<"create">>, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    ?DEBUG(?MODULE_STRING "[~5w] action.~p: create ~p ~p", [ ?LINE, TransId, Type, FilteredArgs ]),
    db:cast(TransId, <<"create">>, module(), [ Type | FilteredArgs ]);

do_action_async(TransId, _, read, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    ?DEBUG(?MODULE_STRING "[~5w] action.~p: read ~p", [ ?LINE, TransId,  FilteredArgs ]),
    db:cast(TransId, <<"read">>, module(), FilteredArgs);

do_action_async(TransId, Any, Action, Args) ->
    FilteredArgs = lists:map(fun hyd:quote/1, Args),
    ?DEBUG(?MODULE_STRING "[~5w] action.~p: Any: ~p Action: ~p Args: ~p", [ ?LINE, TransId, Any, Action, FilteredArgs ]),
    db:cast(TransId, <<"action">>, module(), [ Any, Action | FilteredArgs ]).

%% @doc Generic call runner.
%% Perform the API call and handle various responses.
-spec run(
    Op :: [ tuple() ] ) -> list() | {error, term()}.

run(Op) ->
    case hyd:call(Op) of
        {ok, [<<"0">>]} ->
            [];

        {ok, Elements } ->
            Results = lists:foldl( fun
                ({error, _} = Error, _Acc) ->
                    [ Error ];
                (X, Acc) ->
                    case db_results:unpack(X) of
                        {ok, Result} ->
                            [ Result | Acc ];

                        {ok, Infos, More} ->
                            case db_results:unpack(More) of
                                {ok, Result} ->
                                    [ {Infos, Result} | Acc ];

                                {error, _} = Error ->
                                    [ Error ]
                            end;

                        {error, _} = Error ->
                            [ Error ]
                    end
                end, [], Elements),
            lists:flatten(Results);
            
        _ ->
            internal_error(146)
    end.

-spec parse_indexed(
    Op :: [ tuple() ]) -> {ok, list()} | {error, term()}.

parse_indexed(Op) ->
    case run(Op) of
        [true] ->
            {ok, []};

        [] ->
            {ok, []};

        [{error, _} = Error | _] ->
            ?ERROR_MSG(?MODULE_STRING "[~5w] Backend Error: ~p", [?LINE, Error ]),
            Error;

        [{_Index, _} | _] = Result ->
            ?DEBUG(?MODULE_STRING "[~5w] Result: ~p", [?LINE, Result]),
            Inversed = lists:map(fun({_,V}) ->
                V
            end, Result),
            {ok, lists:reverse( Inversed )};

        _Error ->
            % FIXME handle _Error
            ?ERROR_MSG(?MODULE_STRING "[~5w] Error: ~p", [ ?LINE, _Error ]),
            internal_error(161)
    end.

-spec parse_singleton(
    Op :: list([ term() ]) ) -> {ok, term()} | {error, term()}.

parse_singleton(Op) ->
    case run(Op) of
        [] ->
            {ok, []};

        [{error, _} = Error | _] ->
            ?DEBUG("Backend Error: ~p", [ Error ]),
            Error;

        [ Value | _] ->
            {ok, Value};

        _Error ->
            % FIXME handle _Error
            ?DEBUG("Error: ~p", [ _Error ]),
            internal_error(191)
    end.

internal_error(Code) ->
    internal_error(Code, []).

-spec internal_error(
    Code :: integer(),
    Args :: list() ) -> {error, term()}.

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

%% @doc check the fqid validity (is format valid ?).
%% Null bytes are forbidden -> valid is false.
-spec valid(
    Value :: iodata() | integer() | float()
    ) -> true | false.

valid(read) ->
    true;
valid(Value) when is_list(Value) ->
    correct(Value);
valid(Value) when is_integer(Value) ->
    true;
valid(Value) when is_float(Value) ->
    true;
valid(<<>>) -> 
    true;
valid(Value) when is_binary(Value) ->
    %?DEBUG("valid: Value: ~p", [ ?LINE, Value ]),
    case binary:match(Value,<<0>>) of
         nomatch ->
            true;
        _ ->
            false
    end;
valid(_) ->
    false.

correct(List) when is_list(List) ->
    lists:all(fun valid/1, List);
correct(Elem) ->
    correct([Elem]).

% fqid_head(<<First:1/binary, Rest/bits>>) when
%     First =:= <<"?">>;
%     First =:= <<"@">>;
%     First =:= <<"#">>;
%     First =:= <<"%">>;
%     First =:= <<"&">>;
%     First =:= <<"!">> ->
%     fqid_body(Rest);
% fqid_head(_) ->
%     false.
%     
% fqid_body(Body) ->
%     case binary:match(Body,<<0>>) of
%          nomatch ->
%             true;
%         _ ->
%             false
%     end.
