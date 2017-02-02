-module(db).
% Created db.erl the 13:26:07 (02/05/2014) on core
% Last Modification of db.erl at 13:45:20 (02/02/2017) on core
% 
% Author: "rolph" <rolphin@free.fr>

% Simple wrapper to hide the 'gtmproxy' process

-export([
    call/3, call/4,
    cast/4
]).

-define(debug, true).

-ifdef(debug).
-define(DEBUG(Format, Args),
  io:format(Format ++ " | ~w.~w\n",  Args ++ [?MODULE, ?LINE])).
-else.
-define(DEBUG(Format, Args), true).
-endif.

call(Method, Module, Args) ->
    call(Method, Module, Args, 5000).

call(Method, Module, Args, undefined ) ->
    call(Method, Module, Args, 5000);
    
call(Method, Module, Args, Timeout) ->
    case correct([Method, Module]) of
        true ->
            case correct(Args) of
                true ->
                    do_call(Method, Module, Args, Timeout);

                false ->
                    internal_error(27, [])
            end;

        false ->
            internal_error(31, [])
    end.

do_call(Method, Module, Args, Timeout) ->
    Call = [ Method, Module, Args ],
    catch gen_server:call( gtmproxy, {call, Call}, Timeout).

-spec cast( 
    TransId :: non_neg_integer(),
    Method :: binary(),
    Module :: binary(),
    Args  :: iolist() ) -> ok | {'EXIT', term()} | {error, term()}.

cast(TransId, Method, Module, Args) ->
    case correct([Method, Module]) of
        true ->
            case correct(Args) of
                true ->
                    do_cast(TransId, Method, Module, Args);

                false ->
                    internal_error(47, [])
            end;

        false ->
            internal_error(31, [])
    end.

do_cast(TransId, Method, Module, Args) ->
    catch gen_server:cast(gtmproxy, {self(), [TransId, Method, Module, Args]}).
    
% check the value validity (is format valid ?)
% any null bytes are forbidden -> valid is false.
-spec valid(
    Value :: iodata() | integer()
) -> true | false.

valid(Value) when is_list(Value) ->
    valid(iolist_to_binary(Value));
valid(Value) when is_integer(Value) ->
    true;
valid(Value) when is_binary(Value) ->
    ?DEBUG(?MODULE_STRING ".~p valid: Value: ~p", [ ?LINE, Value ]),
    case binary:match(Value,<<0>>) of
         nomatch ->
            true;
        _ ->
            false
    end.

correct(List) when is_list(List) ->
    lists:all(fun valid/1, List);
correct(Elem) ->
    correct([Elem]).


-spec internal_error(
    Code :: integer(),
    Args :: list() ) -> {error, term()}.

internal_error(Code, Args) ->
    hyd:error(?MODULE, Code, Args).

