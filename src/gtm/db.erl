-module(db).
% Created db.erl the 13:26:07 (02/05/2014) on core
% Last Modification of db.erl at 20:07:26 (09/07/2014) on core
% 
% Author: "rolph" <rolphin@free.fr>

% Simple wrapper to hide the 'gtmproxy' process

-export([
    call/3, call/4
]).

call(Method, Module, Args) ->
    call(Method, Module, Args, 5000).

call(Method, Module, Args, undefined ) ->
    Call = [ Method, Module, Args ],
    catch gen_server:call( gtmproxy, {call, Call});
    
call(Method, Module, Args, Timeout) ->
    Call = [ Method, Module, Args ],
    catch gen_server:call( gtmproxy, {call, Call}, Timeout).
