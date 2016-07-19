-module(hyd).
% Created hyd.erl the 02:16:47 (06/02/2014) on core
% Last Modification of hyd.erl at 09:23:00 (03/11/2015) on core
% 
% Author: "rolph" <rolphin@free.fr>

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
    quote/1,
    unquote/1
]).

-record(operation, {
    method,
    module,
    args,
    timeout
}).


% Create a new operation
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

% try to execute a list of non returning function
% and stop at the first fail
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

% call a list of operation until the end
% collect all results even errors
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

        {ok, <<"0">>} -> % when nothing happens
            call(Ops, Result);

        {ok, Value} ->
            call(Ops, [Value|Result])
    end.

pcall([]) ->
    [];
pcall(Ops) ->
    do_pcall(Ops).
    
do_call( #operation{ method=Method, module=Module, args=Args, timeout=Timeout} ) ->
    %io:format("DEBUG: ~p ~p ~p\n", [ Method, Module, Args ]),
    db:call( Method, Module, Args, Timeout );
do_call( _ ) ->
    {error, badarg}.


reload(Module) ->
    Op = #operation{
        method=[],
        module= <<"reload">>,
        args=[Module] },

    do_call( Op ).

% Safety first
quote(true) -> <<"true">>;
quote(false) -> <<"false">>;
quote(Value) when is_float(Value) ->
    float_to_list(Value);
quote(Value) when is_binary(Value) ->
    binary:replace(Value, <<"\"">>, <<31>>, [global]);
quote(Value) when is_integer(Value) ->
    Value.

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

hash_name( Name ) when is_atom(Name) ->
    hash_name( atom_to_list(Name) );
hash_name( Name ) when is_list(Name) ->
    list_to_binary( [ A || A <- Name, not lists:member(A,"aeiouy_") ]).

% explore generic method

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

