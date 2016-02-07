-module(login_handler).
% Created login_handler.erl the 14:27:47 (16/08/2015) on core
% Last Modification of login_handler.erl at 20:47:32 (17/08/2015) on core
% 
% Author: "rolph" <rolphin@free.fr>

%-behaviour(cowboy_http_handler).

-include("logger.hrl").

-export([
    init/3,
    handle/2,
    terminate/3
]).

-record(state, {
    count
}).

init(_Type, Req, _Opts) ->
    {ok, Req, #state{count=0}}.

handle(Req, State) ->
    {Method, Req2} = cowboy_req:method(Req),
    Body = cowboy_req:has_body(Req),
    ?DEBUG(?MODULE_STRING " Method: ~p", [ Method ]),
    response(Method, Body, Req2, State).

response(<<"GET">>, _, Req, #state{count=Count} = State) ->
    {PathInfo, Req2} = cowboy_req:path_info(Req),
    [ Login, Domain, Session |_  ] = PathInfo,
    Response = case ejabberd_sm:get_user_ip(Login, Domain, Session) of
        undefined ->
            <<"{}">>;
        Ip ->
            ?DEBUG(?MODULE_STRING " Session: ~p", [ Ip ]),
            UserInfos = hyd_users:info(Login),
            sockjs_json:encode(UserInfos)
    end,
    {ok, Req3} = cowboy_req:reply(200, [
        {<<"content-type">>, <<"application/json">>}
        ], Response, Req2),
    {ok, Req3, State#state{count=Count+1}};

response(<<"POST">>, true, Req, #state{count=Count} = State) ->
    {ok, PostVals, Req2} = cowboy_req:body_qs(Req),
    ?DEBUG(?MODULE_STRING " PostVals: ~p", [ PostVals ]),
    Id = grab(<<"id">>, PostVals),
    Token = grab(<<"token">>, PostVals),
    UserInfos = hyd_users:internal(Id),
    {ok, Req3} = cowboy_req:reply(200, [
        {<<"content-type">>, <<"application/json">>}
        ], sockjs_json:encode(UserInfos), Req2),
    {ok, Req3, State#state{count=Count+1}}.

terminate(_Reason, _Req, #state{count=Count}) ->
    ?DEBUG(?MODULE_STRING " Login handler: handled : ~p requests\n", [ Count ]),
    ok.
    
grab(Key,Values) ->
    case lists:keyfind(Key, 1, Values) of
        {Key, Value} ->
            Value;
        _ ->
            []
    end.

