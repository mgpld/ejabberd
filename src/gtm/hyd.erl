%%
%% Created hyd.erl the 02:16:47 (06/02/2014) on core
%% Last Modification of hyd.erl at 10:14:23 (10/06/2017) on core
%% 
%% @author rolph <rolphin@free.fr>
%% @doc Thin layer between db and callers.
%% Performs the low level calls.

-module(hyd).

-export([
    cast/1,
    call/1,
    pcall/1,
    reload/1,
    error/2, error/3,
    operation/3, operation/4,
    explore/2, explore/3, explore/4, explore/5
]).

-export([
    run/1,
    quote/1,
    unquote/1
]).

-record(operation, {
    method,
    module,
    args,
    timeout
}).


%% @doc Create a new operation.
operation(Method, Module, Args) ->
    operation( Method, Module, Args, undefined ).

-spec operation(
    Method::list() | binary(),
    Module::list() | binary(),
    Args::list( integer() | list() | binary()  ),
    Timeout::non_neg_integer() | infinity | undefined) -> #operation{}.

operation( Method, Module, Args, Timeout ) ->
    #operation{
	method=Method,
	module=Module,
	args=Args,
	timeout=Timeout}.

%% @doc Try to execute a list of non returning function.
%% Stop at the first fail.
-spec cast(
    Operations :: list() ) -> ok | {error, term()}.

cast([]) ->
    ok;
cast([Op|Ops]) ->
    case do_call(Op) of
        {error, Error} ->
            {error, {Op, Error}};
        
        % {ok, <<>>} -> % when empty result
        %    call(Ops, Result);

        {ok, <<"0">>} ->
            cast(Ops);

        {ok, Value} -> % the true success is <<"0">>
            {error, {Op, Value}}

    end.

%% @doc Call a list of operation until the end.
%% Collect all results even errors.
-spec call(
    Operations :: list() ) -> list({ok, term()} | {error, term()}).

call(Ops) ->
    call(Ops, []).

call([], Result) ->
    {ok, Result};
call([ Op | Ops ], Result) ->
    case do_call( Op ) of
        {error, Error} ->
            call(Ops, [ {error, {Op, Error} } | Result]);
        
        {ok, <<>>} -> % when empty result
            call(Ops, Result);

        {ok, <<"f">>} ->
            call(Ops, [false|Result]);

        {ok, <<"t">>} ->
            call(Ops, [true|Result]);

        {ok, <<"0">>} -> % when nothing happens
            call(Ops, Result);

        {ok, Value} ->
            call(Ops, [Value|Result]);

%%        {'EXIT', {timeout,{gen_server,call,[gtmproxy,{call,[<<"actionArgs">>,<<"fqids">>,[<<"#0004564303RdTJZPD4AY2cwGa364303i58720">>,<<"getInfos">>,<<"61">>]]}]}}}
%%
        {'EXIT', Error} ->
            call(Ops, [ {error, {Op, Error} } | Result])

    end.

pcall([]) ->
    [];
pcall(Ops) ->
    do_pcall(Ops).
    
%% @doc Perform a low level db call.
%% Extract information from #operation{} and call the low level engine backend.

do_call( #operation{ method=Method, module=Module, args=Args, timeout=Timeout} ) ->
    db:call( Method, Module, Args, Timeout );
do_call( _ ) ->
    {error, badarg}.

%% @doc Force reload a module.
%% For a module to reload itself.
%% Reloading make the updated code be installed.
reload(Module) ->
    Op = #operation{
        method=[],
        module= <<"reload">>,
        args=[Module] },

    do_call( Op ).

%% @doc Safety first.
%% Quote parameters before being sent to low level.
%% The '"' is being transformed by the arbitrary character char(31).
%% The reverse operation is done by the extraction.
quote(true) -> <<"true">>;
quote(false) -> <<"false">>;
quote(Value) when is_float(Value) ->
    float_to_list(Value);
quote(Value) when is_binary(Value) ->
    binary:replace(Value, <<"\"">>, <<31>>, [global]);
quote(Value) when is_integer(Value) ->
    Value.

%% @doc Reverse quote operation.
%% Transform char(31) into '"'.
%% Handle binary(), and key value list of binaries.
unquote(Value) when is_binary(Value) ->
    binary:replace(Value, <<31>>, <<"\"">>, [global]);

unquote({Key, Value}) when is_binary(Value) ->
    {Key, binary:replace(Value, <<31>>, <<"\"">>, [global])};

unquote({Key, Values}) when is_list(Values) ->
    {Key, unquote(Values)};

unquote([{_K,_V} | _ ] = Values) ->
    lists:map(fun unquote/1, Values);

unquote([ _V | Rest ]) ->
    lists:map(fun unquote/1, Rest).

% (ejabberd@localhost)227> hyd:pcall([hyd:operation(<<"info">>,<<"users">>,[1001]),hyd:operation(<<"info">>,<<"users">>,[1002])]).
do_pcall(Ops) ->
    Ps = [spawn_monitor(fun() -> exit({ok, do_call(X) }) end) || X <- Ops], 
    [receive {'DOWN',Ref,_,_,{ok,R}} -> R after 10000 -> error(timeout) end || {_,Ref} <- Ps].

% unquote(Value) ->
 %   Value.

-spec error(
    Module :: list() | atom(),
    Code :: integer() ) -> {error, term()}.

error(Module, Code) when is_integer(Code) ->
    fmt_error(Module, integer_to_binary( Code ), [] ).

-spec error(
    Module :: list() | atom(),
    Code :: integer(),
    Args :: list() ) -> {error, term()}.

error(Module, Code, Args) when is_integer(Code) ->
    fmt_error(Module, integer_to_binary( Code ), Args ).

fmt_error(Module, Code, []) ->
    Source = hash_name(Module),
    Error = iolist_to_binary([ Source, Code ]),
    {error, [ 
        {<<"code">>, Error },
        {<<"description">>, <<"internal error">>} ]};

fmt_error(Module, Code, Args) ->
    Source = hash_name(Module),
    Error = iolist_to_binary([ Source, Code ]),
    {error, [ 
        {<<"code">>, Error },
        {<<"description">>, <<"internal error">>},
        {<<"arguments">>, Args} ]}.

%% @doc Compute hash in module names.
%% @deprecated Unused.
hash_name( Name ) when is_atom(Name) ->
    hash_name( atom_to_list(Name) );
hash_name( Name ) when is_list(Name) ->
    list_to_binary( [ A || A <- Name, not lists:member(A,"aeiouy_") ]).

%% @doc explore generic method.
%% @deprecated Unused.
explore(Module, Userid) ->
    explore(Module, Userid, 50).

explore(Module, Userid, Count) ->
    explore(Module, Userid, Count, <<"up">>).

explore(Module, Userid, Count, Way) ->
    explore(Module, Userid, Count, Way, 0).

explore(Module, Userid, Count, Way, From) ->
    Ops = [
        hyd:operation(<<"explore">>, Module, [ Userid, Count, Way, From ])
    ],
    run(Ops).

run(Op) ->
    case hyd:call(Op) of
        {ok, Elements } ->
            
            case lists:foldl( fun
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
                end, [], Elements) of

                    {error, _} = Error ->
                        Error;

                    Results when is_list(Results) ->
                        lists:flatten(Results)
                end;
            
        _ ->
            internal_error(833, Op)
    end.

internal_error(Code) ->
    hyd:error(?MODULE, Code).

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

