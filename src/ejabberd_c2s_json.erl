%%%----------------------------------------------------------------------
%%% File    : ejabberd_c2s_json.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : Serve C2S connection
%%% Created : 16 Nov 2002 by Alexey Shchepin <alexey@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2012   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_c2s_json).
-author('ak@harmonygroup.net').
-update_info({update, 0}).

-define(GEN_FSM, p1_fsm).

-behaviour(?GEN_FSM).

% extracted from ejabberd_sm.erl
-record(session, {sid, usr, us, priority, info}).

%% External exports
-export([start/2,
    stop/1,
    start_link/2,
    send_text/2,
    send_element/2,
    socket_type/0,
    get_presence/1,
    get_aux_field/2,
    set_aux_field/3,
    del_aux_field/2,
    get_subscription/2,
    broadcast/4,
    get_subscribed/1]).

%% gen_fsm callbacks
-export([init/1,
    session_established/2,
    authorized/2,
    handle_event/3,
    handle_sync_event/4,
    code_change/4,
    handle_info/3,
    terminate/3,
    print_state/1
]).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("mod_privacy.hrl").
-include("logger.hrl").

-define(SETS, gb_sets).
-define(DICT, dict).

-define(OPERATION_NEXT, 1).
-define(OPERATION_ANSWER, 2).
-define(OPERATION_SCORE, 3).

-define(OPERATION_GETCONTACTLIST, 20).
-define(OPERATION_GETCONTACTTREE, 21).
-define(OPERATION_GETCONTACTSFROMCATEGORY, 211).
-define(OPERATION_GETINVITATIONS, 212).
-define(OPERATION_GETOTHERCONTACTTREE, 213).
-define(OPERATION_ADDCONTACT, 22).
-define(OPERATION_ADDCONTACTINCATEGORY, 23).
-define(OPERATION_GETCATEGORIES, 24).
-define(OPERATION_GETCONTACTINFO, 25).
-define(OPERATION_SETINFO, 26).
-define(OPERATION_SETLABEL, 261).
-define(OPERATION_DELETEINFO, 262).
-define(OPERATION_SETINFO_TMP, 263).
-define(OPERATION_CANCEL, 2631).
-define(OPERATION_VALIDATE, 2632).
-define(OPERATION_CONTRACT, 2633).
-define(OPERATION_GETCONTACTINFOBIS, 27).
-define(OPERATION_ISFAVORITE, 271).
-define(OPERATION_INVITECONTACT, 28).
-define(OPERATION_ACCEPTCONTACT, 280).
-define(OPERATION_REFUSEINVITATION, 2801).
-define(OPERATION_CANCELINVITATION, 2802).
-define(OPERATION_BLOCKCONTACT, 281).
-define(OPERATION_LISTBLOCKED, 2811).
-define(OPERATION_UNBLOCKCONTACT, 282).
-define(OPERATION_DELETECONTACT, 29).
-define(OPERATION_DELETECONTACTINFO, 291).

-define(OPERATION_SETCONFIGURATION, 30).
-define(OPERATION_GETCONFIGURATION, 31).
-define(OPERATION_GETCONFIGURATION_VALUE, 32).
-define(OPERATION_SETCONFIGURATION_VALUE, 33).
-define(OPERATION_RESETCONFIGURATION_VALUE, 34).

-define(OPERATION_SETREGISTRY_VALUE, 35).
-define(OPERATION_GETREGISTRY_VALUE, 36).

-define(OPERATION_GETPROFILETREE, 40).
-define(OPERATION_RESTOREPROFILE, 41).
-define(OPERATION_STOREPROFILE, 42).
-define(OPERATION_SETPROFILE, 43).
-define(OPERATION_DELETEPROFILE, 431).
-define(OPERATION_DELPROFILECATEGORY, 432).
-define(OPERATION_GETPROFILE, 44).
-define(OPERATION_GETPROFILELIST, 45).
-define(OPERATION_SETPROFILEPRESENCE,46).

-define(OPERATION_GETSCHEDULE, 50).
-define(OPERATION_GETPROPERTIES, 60).

-define(OPERATION_SETVISIBILITY_VALUE, 70).
-define(OPERATION_SETVISIBILITY, 701).
-define(OPERATION_SETVISIBILITY_TMP, 702).
-define(OPERATION_GETVISIBILITY_VALUE, 71).

% Retrieve information about a user 
-define(OPERATION_GETUSERINFOS, 80).
-define(OPERATION_ABOUT, 81).

-define(OPERATION_GETALLINTERNALDATA, 2).

-define(THREAD_LIST, 90).
-define(THREAD_TREE, 91).
-define(THREAD_SEARCH, 92).
-define(THREAD_BOUNDS, 93).
-define(THREAD_GETMESSAGE, 94).
-define(THREAD_SUBSCRIBERS, 95).
-define(THREAD_SUBSCRIBE, 96).
-define(THREAD_UNSUBSCRIBE, 97).

-define(OPERATION_GETLABELS, 100).

-define(OPERATION_SEARCH_NEW, 110).
-define(OPERATION_SEARCH_QUERY, 111).

-define(GENERIC_EXPLORE, 12).

%% roles
-define(ROLE_SUPERVISOR, 1).

-define(TEST, false).

%% pres_a contains all the presence available send (either through roster mechanism or directed).
%% Directed presence unavailable remove user from pres_a.
-record(state, {
    socket,
    sockmod,
    socket_monitor,
    db,
    timeout,
    sasl_state = 0,
    access,
    shaper,
    zlib = false,
    authenticated = false,
    jid,
    user = [], 
    server = ?MYNAME, 
    resource = [],
    userid = 0,
    sid,
    pres_t = ?SETS:new(),
    pres_f = ?SETS:new(),
    pres_a = ?SETS:new(),
    pres_i = ?SETS:new(),
    pres_last, pres_pri,
    pres_timestamp,
    pres_invis = false,
    privacy_list = #userlist{},
    conn = undefined,
    auth_module = undefined,
    ip,
    aux_fields = [],
    lang}).

%-define(DBGFSM, true).

-ifdef(DBGFSM).
-define(FSMOPTS, [{debug, [trace]}]).
-else.
-define(FSMOPTS, []).
-endif.

%% Module start with or without supervisor:
-ifdef(NO_TRANSIENT_SUPERVISORS).
-define(SUPERVISOR_START, ?GEN_FSM:start(ejabberd_c2s_json, [SockData, Opts],
					 fsm_limit_opts(Opts) ++ ?FSMOPTS)).
-else.
-define(SUPERVISOR_START, supervisor:start_child(ejabberd_c2s_sup,
						 [SockData, Opts])).
-endif.

%% This is the timeout to apply between event when starting a new
%% session:
-define(C2S_OPEN_TIMEOUT, 60000).
-define(C2S_HIBERNATE_TIMEOUT, 60000 * 5). % 2 minutes of inactivity FIXME Now it unlogg the user
% -define(C2S_AUTHORIZED_TIMEOUT, 60000 * 15). % 15 minutes of inactivity
-define(C2S_AUTHORIZED_TIMEOUT, 60000 * 10). % 10 min of inactivity

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start(SockData, Opts) ->
    ?SUPERVISOR_START.

start_link(SockData, Opts) ->
    ?GEN_FSM:start_link(ejabberd_c2s_json, [SockData, Opts],
            fsm_limit_opts(Opts) ++ ?FSMOPTS).

socket_type() ->
    raw.

%% Return Username, Resource and presence information
get_presence(FsmRef) ->
    ?GEN_FSM:sync_send_all_state_event(FsmRef, {get_presence}, 1000).

get_aux_field(Key, #state{aux_fields = Opts}) ->
    case lists:keysearch(Key, 1, Opts) of
        {value, {_, Val}} ->
            {ok, Val};
        _ ->
            error
    end.

set_aux_field(Key, Val, #state{aux_fields = Opts} = State) ->
    Opts1 = lists:keydelete(Key, 1, Opts),
    State#state{aux_fields = [{Key, Val}|Opts1]}.

del_aux_field(Key, #state{aux_fields = Opts} = State) ->
    Opts1 = lists:keydelete(Key, 1, Opts),
    State#state{aux_fields = Opts1}.

get_subscription(From = #jid{}, StateData) ->
    get_subscription(jlib:jid_tolower(From), StateData);
get_subscription(LFrom, StateData) ->
    LBFrom = setelement(3, LFrom, ""),
    F = ?SETS:is_element(LFrom, StateData#state.pres_f) orelse
        ?SETS:is_element(LBFrom, StateData#state.pres_f),
    T = ?SETS:is_element(LFrom, StateData#state.pres_t) orelse
       ?SETS:is_element(LBFrom, StateData#state.pres_t),
    if F and T -> both;
       F -> from;
       T -> to;
       true -> none
    end.

broadcast(FsmRef, Type, From, Packet) ->
    FsmRef ! {broadcast, Type, From, Packet}.

stop(FsmRef) ->
    ?GEN_FSM:send_event(FsmRef, closed).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_fsm
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}
%%----------------------------------------------------------------------
init([{SockMod, Socket}, Opts]) ->
    %?DEBUG(?MODULE_STRING " Init SockMod: ~p Socket: ~p, Opts: ~p", [ SockMod, Socket, Opts ]),
    Access = case lists:keysearch(access, 1, Opts) of
        {value, {_, A}} -> A;
        _ -> all
    end,
    Shaper = case lists:keysearch(shaper, 1, Opts) of
        {value, {_, S}} -> S;
        _ -> none
    end,

    Zlib = lists:member(zlib, Opts),
    IP = peerip(SockMod, Socket),
    %% Check if IP is blacklisted:
    case is_ip_blacklisted(IP) of
        true ->
            ?INFO_MSG(?MODULE_STRING " Connection attempt from blacklisted IP: ~s (~w)",
                  [jlib:ip_to_list(IP), IP]),
            {stop, normal};

        false ->

            %% Init the seqid count
            put(seqid,-1),

            SocketMonitor = SockMod:monitor(Socket),

            %% Retrieve the hyd node
            %%handle_event({db, set}, undefined, #state{}),
        
            {ok, session_established, #state{
                socket         = Socket,
                sockmod        = SockMod,
                socket_monitor = SocketMonitor,
                db             = get(node),
                zlib           = Zlib,
                timeout        = ?C2S_AUTHORIZED_TIMEOUT,
                access         = Access,
                shaper         = Shaper,
                ip             = IP}, ?C2S_OPEN_TIMEOUT}
    end.

%% Return list of all available resources of contacts,
get_subscribed(FsmRef) ->
    ?GEN_FSM:sync_send_all_state_event(FsmRef, get_subscribed, 1000).

%%----------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%%----------------------------------------------------------------------

% New login mechanism
session_established({login, SeqId, Args}, StateData) ->
    
    Id = fxml:get_attr_s(<<"id">>, Args),
    Password = fxml:get_attr_s(<<"pass">>, Args),
    %Token = fxml:get_attr_s(<<"token">>, Args), %% Token is for rebinding or login
    Now = os:timestamp(),
    
    SID = {Now, self()},
    Conn = get_conn_type(StateData),
    Info = [{ip, StateData#state.ip}, {conn, Conn},
        {auth_module, StateData#state.auth_module}],

    ?DEBUG(?MODULE_STRING " [LOGIN (~p/~p)] Id: ~p\nServer: ~s\nUser: ~s\nResource: ~s\nJid: ~p", [ 
        seqid(),
        SeqId,
        Id, 
        StateData#state.server,
        StateData#state.user,
        StateData#state.resource,
        StateData#state.jid
    ]),

    % [GTM] Store this connection
    {Ip, Port} = StateData#state.ip,
    Userip = list_to_binary(fmt_ip(Ip)),
    Userport = Port,

    TmpState = StateData#state{
        authenticated=false,
        userid=Id
    },


    R = base64:encode(term_to_binary(Now)),
    % #jid{lserver=LoginServer, luser=LoginUser} = IdJid = jlib:string_to_jid(Id),
    DataId = case binary:split(Id, <<"@">>, [ global ]) of
         [ LoginUser, LoginServer ] ->
            %jlib:string_to_jid(<<LoginUser/binary, "@", LoginServer/binary>>);
            userid(TmpState, LoginUser, LoginServer, Password);
        
        [ LoginUser, _Domain, LoginServer | _ ] ->
            % IdJid = jlib:string_to_jid(<<LoginUser/binary, "@", LoginServer/binary>>),
            userid(TmpState, <<LoginUser/binary, "@", _Domain/binary>>, LoginServer, Password)

    end,

    IdJid = undefined,

    case DataId of
        {error, invalid} ->
            ?INFO_MSG(?MODULE_STRING " LOGIN FAIL: invalid user: ~p domain: ~p", [ LoginUser, LoginServer ]),
            Answer = make_answer(SeqId, [
                {<<"status">>, <<"ko">>}, 
                {<<"success">>, <<"false">>}, 
                {<<"connection">>,<<"close">>},
                {<<"error">>, [
                    {<<"description">>, <<"invalid user">>},
                    {<<"code">>, 404}
                    ]
                }]),
            send_element(TmpState, (Answer)),
            receive after 1000 -> ok end, % Sending the error packet before closing the connection
            {stop, normal, TmpState#state{ jid = IdJid }};

        {error, Reason} ->
            Answer = make_answer(SeqId, [
                {<<"status">>, <<"ko">>}, 
                {<<"success">>, <<"false">>}, 
                {<<"connection">>,<<"close">>},
                {<<"error">>, {struct, [
                    {<<"description">>, <<"technical issue">>},
                    {<<"code">>, 500}
                    ]}
                }]),
            send_element(TmpState, (Answer)),
            receive after 1000 -> ok end, % Sending the error packet before closing the connection
            ?ERROR_MSG(?MODULE_STRING "[~5w] Problem retrieving userid: ~p", [ ?LINE, Reason ]),
            {stop, normal, TmpState#state{ jid = IdJid }};

        {ok, UserId} ->

            % create the session - synchronous call
            data_specific(TmpState, hyd_users, session_init, [ Userip, Userport ]),

            % [GTM] every data inside the "visible" category
            %UserInfos = case data_specific(TmpState, hyd_users, info, [ UserId, <<"visible">> ]) of
            UserInfos = case data_specific(TmpState, hyd_users, internal, [ UserId ]) of
                [] ->
                    [];

                {ok, Result} ->
                    Result
            end,

            %% FIXME UserId, UserIdent etc
            ?INFO_MSG(?MODULE_STRING " Registering session\nSID: ~p\nUserIdent: ~p@~p\nInfos: ~p\nResource: ~s\nInfo: ~p", [ 
                SID, UserId, 
                TmpState#state.server,
                UserInfos, %IdJid#jid.lserver, 
                R, Info ]),

            ejabberd_sm:open_session(SID, UserId, TmpState#state.server, R, Info),

            % [GTM] Logging the newly created session
            % Let it crash because recording user activity is MANDATORY
            {ok, SessionInfos} = data_specific(TmpState, hyd_users, session_new, [ R, UserId, Userip, Userport ]),

            Username = <<UserId/binary,"@",(TmpState#state.server)/binary>>,
            Answer = make_answer(SeqId, 200, [
                {<<"session">>, R},
                {<<"username">>, Username},
                {<<"domain">>, TmpState#state.server},
                {<<"id">>, UserId},
                {<<"timeout">>, ?C2S_AUTHORIZED_TIMEOUT}, %% TODO add module_info(attributes) -> vsn
                {<<"infos">>, UserInfos} | SessionInfos ]),
                %{<<"infos">>, {struct, UserInfos}} | SessionInfos ]),
            %send_element(TmpState, (Answer)),
            send_element(TmpState, Answer),


            % Find the reverse dns entry
            spawn( fun() ->
                case inet_res:lookup(Ip, in, ptr, [], 5000) of
                    [] -> ok;
                    [Reverse|_] ->
                        data_specific(TmpState, hyd_users, session_dns, [ Userip, Reverse ])
                end
            end),

            Online = initial_presence(TmpState, Username, [], UserId),
            Status = <<"online">>,
            UserJid = jlib:string_to_jid(Username),

            % Increment command seqid 
            seqid(1),

            fsm_next_state(authorized, TmpState#state{
                jid = UserJid, %% #jid{}
                sid = SID,
                pres_f = ?SETS:from_list(Online),
                resource = R,
                authenticated = true,
                access = Status,
                userid = UserId,
                user = Username})
    end;

session_established({action, SeqId, Args}, State) when is_list(Args) ->
    case fxml:get_attr_s(<<"operation">>, Args) of
        <<>> ->
            fsm_next_state(session_established, State);
            
        <<"login">> = Operation->
            ?DEBUG(?MODULE_STRING "[~5w] Login with args: ~p", [ ?LINE, Args ]),
            NewState = handle_query(Operation, SeqId, Args, State),
            fsm_next_state(session_established, NewState);
            %Params = [],
            %hyd_fqids:action_async(SeqId, Element, Action, [ 0 | Params ]),
            %Actions = State#state.aux_fields,
            %NewState = State#state{aux_fields=[{SeqId, [ Element, Action, Params ]} | Actions ]},
            %fsm_next_state(session_established, NewState);

        _ ->
            Answer = make_error(undefined, SeqId, 404, <<"invalid call">>),
            send_element(State, Answer),
            fsm_next_state(session_established, State)
        
    end;

%% We hibernate the process to reduce memory consumption after a
%% configurable activity timeout
session_established(timeout, StateData) ->
%    Options = [],
%    proc_lib:hibernate(?GEN_FSM, enter_loop,
%        [?MODULE, Options, session_established, StateData]),
%    fsm_next_state(session_established, StateData);
    {stop, normal, StateData};

session_established(closed, StateData) ->
    {stop, normal, StateData};

session_established(_Any, StateData) ->
    ?ERROR_MSG("Closing on ~p", [ _Any ]),
    {stop, normal, StateData}.

% FIXME should be done in ejabberd_sockjs.erl
authorized({presence, SeqId, {struct, Args}}, StateData) ->
    authorized({presence, SeqId,  Args}, StateData);

authorized({presence, SeqId, Args}, StateData) ->

    case args(Args, [<<"contactlist">>, <<"value">>]) of
        [ List, Status ] ->
            %?DEBUG(?MODULE_STRING " [~p] presence on ~p : ~p", [ StateData#state.user, List, Status ]),
            publish_presence( StateData, List, Status ),
            Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
            send_element(StateData, (Answer)),
            seqid(1),
            fsm_next_state(authorized, StateData);

        _ ->
            Answer = make_answer(SeqId, [{<<"status">>, <<"ko">>}]),
            send_element(StateData, (Answer)),
            seqid(1),
            fsm_next_state(authorized, StateData)
    end;
        
   %Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
   %% send presence to all our StateData#state.pres_f
   %?DEBUG(?MODULE_STRING " [~p (~p)] Contacts: ~p\n", [ 
   %     StateData#state.user, seqid(),
   %     ?SETS:to_list( StateData#state.pres_f ) ]),

   %publish_presence( Args, StateData ),

   %send_element(StateData, (Answer)),
   %seqid(1),
   %fsm_next_state(authorized, StateData#state{ access=Args });

authorized({action, SeqId, <<"ping">>}, StateData) ->
    Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
    send_element(StateData, (Answer)),
    seqid(1),
    fsm_next_state(authorized, StateData);

authorized({action, SeqId, <<"supervise">>}, StateData) ->
    Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
    send_element(StateData, Answer),
    fsm_next_state(authorized, StateData#state{ sasl_state = ?ROLE_SUPERVISOR });

authorized({action, SeqId, Args}, StateData) when is_list(Args) ->
    case fxml:get_attr_s(<<"type">>, Args) of
        <<"logout">> ->
            Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
            send_element(StateData, (Answer)),
            receive after 1000 -> ok end, % Sending the error packet before closing the connection
            {stop, normal, StateData};

        <<"info">> ->
            case  fxml:get_attr_s(<<"id">>, Args) of
                <<>> ->
                    Answer = make_error(undefined, SeqId, 404, <<"invalid call, missing id">>),
                    send_element(StateData, (Answer)),
                    fsm_next_state(authorized, StateData);

                Id ->
                    Params = [ Id, StateData#state.userid ],
                    Operation = read,
                    hyd_fqids:action_async(SeqId, Id, Operation, Params),
                    Actions = StateData#state.aux_fields,
                    fsm_next_state(authorized, StateData#state{aux_fields=[{SeqId, [ Id, Operation, Params ]} | Actions ]})
            end;

        <<"stats">> ->
            case  fxml:get_attr_s(<<"id">>, Args) of
                <<>> ->
                    Answer = make_error(undefined, SeqId, 404, <<"invalid call">>),
                    send_element(StateData, (Answer)),
                    fsm_next_state(authorized, StateData);

                Id ->
                    case data_specific(StateData, hyd_fqids, stats, [ Id, StateData#state.userid ]) of
                        {error, Reason} ->
                            ?ERROR_MSG(?MODULE_STRING "[~5w] Info: error: ~p", [ ?LINE, Reason ]),
                            Answer = make_error(Reason, SeqId, 500, <<"internal server error">>),
                            send_element(StateData, (Answer)),
                            fsm_next_state(authorized, StateData);

                        {ok, []} ->
                            Answer = make_answer_not_found(SeqId),
                            send_element(StateData, (Answer)),
                            fsm_next_state(authorized, StateData);

                        {ok, Result} ->
                            %?DEBUG(?MODULE_STRING "[~5w] Info: returns: ~p", [ ?LINE, Result ]),
                            Answer = make_answer(SeqId, 200, Result),
                            send_element(StateData, (Answer)),
                            fsm_next_state(authorized, StateData);

                        [] ->
                            ?ERROR_MSG(?MODULE_STRING "[~5w] 'info': returns empty for ~p", [ ?LINE, Id ]),
                            Answer = make_answer_not_found(SeqId),
                            send_element(StateData, (Answer)),
                            fsm_next_state(authorized, StateData)
                    end
            end;

        <<"new-discussion">> ->
            %DiscussionId = integer_to_list(erlang:phash2(os:timestamp(), 999999999), 5),
            %Discussion = list_to_binary(DiscussionId),
            %Discussion = base64:encode(term_to_binary(os:timestamp())),
            
            % FIXME need a cleanup process when a room pg2 group is no longuer needed !
            RoomId = 0,
            %?DEBUG(?MODULE_STRING " Room: New room: ~p", [ RoomId ]),

            #jid{luser=User, lserver=Host} = StateData#state.jid,
            UserName = binary_to_list(User) ++ "@" ++ binary_to_list(Host),
            Ref = base64:encode(lists:concat(tuple_to_list(os:timestamp()))),
            ?DEBUG(?MODULE_STRING " Creating the room: '~p' on '~p' owner: ~p", [ Ref, Host, UserName ]),
            mod_chat:create_room(Host, RoomId, UserName, Ref, []),

            %% FIXME new-discussion is not javascript friendly name
            Answer = make_answer(SeqId, [{<<"new-discussion">>, Ref}]),
            send_element(StateData, (Answer)),

            fsm_next_state(authorized, StateData);

        <<"configuration">> ->
            case  fxml:get_attr_s(<<"id">>, Args) of
            <<>> ->
                case fxml:get_attr_s(<<"operation">>, Args) of
                    <<"list">> ->
                        case handle_configuration(list, undefined, Args, StateData) of
                            {[], _} ->
                                Answer = make_answer_not_found(SeqId),
                                send_element(StateData, Answer),
                                fsm_next_state(authorized, StateData);

                            {Result, _} ->
                                %?DEBUG(?MODULE_STRING " handle_configuration: result: ~p", [ Result ]),
                                Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                                send_element(StateData, (Answer)),
                                fsm_next_state(authorized, StateData);

                            _ ->
                                fsm_next_state(authorized, StateData)
                        end;

                    _ ->
                        fsm_next_state(authorized, StateData)
                end;

            Id ->
                case handle_configuration(Id, Args, StateData) of
                    {Result, NewStateData} ->
                        case Result of 
                            [] ->
                                Answer = make_answer_not_found(SeqId),
                                send_element(NewStateData, Answer),
                                fsm_next_state(authorized, NewStateData);

                            ok ->
                                ?DEBUG(?MODULE_STRING " handle_configuration: set operation: ~p", [ ok ]),
                                Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                                send_element(NewStateData, (Answer)),
                                fsm_next_state(authorized, NewStateData);

                            {ok, Data} ->
                                ?DEBUG(?MODULE_STRING " handle_configuration: result: ~p", [ Data ]),
                                Answer = make_answer(SeqId, [{<<"result">>, Data}]),
                                send_element(NewStateData, (Answer)),
                                fsm_next_state(authorized, NewStateData);

                            false ->
                                fsm_next_state(authorized, NewStateData)

                        end;

                    _ ->
                        fsm_next_state(authorized, StateData)
                end
	        end;
	
        <<"visibility">> ->
            case  fxml:get_attr_s(<<"id">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

            Id ->
                case handle_visibility(Id, Args, StateData) of
                    {Result, NewStateData} ->
                        case Result of 
                        [] ->
                            Answer = make_answer_not_found(SeqId),
                            send_element(NewStateData, (Answer)),
                            fsm_next_state(authorized, NewStateData);

                        _ ->
                            ?DEBUG(?MODULE_STRING " handle_visibility: result: ~p", [ Result ]),
                            Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                            send_element(NewStateData, (Answer)),
                            fsm_next_state(authorized, NewStateData)
                        end;

                    _ ->
                        fsm_next_state(authorized, StateData)
                end
            end;

        <<"leave-discussion">> ->
            case fxml:get_attr_s(<<"discussionid">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                DiscussionId ->
                    From = jlib:jid_to_string(StateData#state.jid),
                    Json = 
                    {struct,[{<<"message">>,
                      {struct,[{<<"type">>,<<"discussion-presence">>},
                           {<<"action">>,<<"leave">>},
                           {<<"from">>,
                        {struct,[{<<"id">>, From},
                             {<<"userid">>, StateData#state.userid},
                             {<<"user">>, StateData#state.user}]}},
                           {<<"discussionid">>,DiscussionId}]}}]},

                    #jid{luser=_User, lserver=Host} = StateData#state.jid,
                    mod_chat:route(Host, DiscussionId, From, del, [StateData#state.jid]),

                    % Answer = make_answer(SeqId, [{<<"discussionid">>, DiscussionId}]),
                    send_element(StateData, (Json)),
                    fsm_next_state(authorized, StateData)
            end;

        <<"join-discussion">> ->
            case fxml:get_attr_s(<<"discussionid">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                DiscussionId ->
                    ?DEBUG(?MODULE_STRING " Join-discussion: ~p", [ DiscussionId ]),

                    From = jlib:jid_to_string(StateData#state.jid),
                    #jid{luser=_User, lserver=Host} = StateData#state.jid,
                    UserName = jid_to_username(StateData#state.jid),
                    mod_chat:route(Host, DiscussionId, From, add, [UserName]),

                    Answer = make_answer(SeqId, [{<<"discussionid">>, DiscussionId}]),
                    send_element(StateData, (Answer)),

                    fsm_next_state(authorized, StateData)

                end;

        <<"quizz">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
            <<>> ->
                fsm_next_state(authorized, StateData);

            Operation ->
                handle_quizz(Operation, SeqId, Args, StateData),
                fsm_next_state(authorized, StateData)
           end;

        % NEW API v2 'contact'
        <<"contact">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_contact(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        % NEW API v2 'profile'
        <<"profile">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_profile(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
           end;

        <<"room">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_room(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
           end;

        <<"groupchat">> ->
            case fxml:get_attr_s(<<"to">>, Args) of
            <<>> ->
                fsm_next_state(authorized, StateData);

            Group ->
                handle_chat(Group, SeqId, Args, StateData),
                fsm_next_state(authorized, StateData)
           end;

        <<"privchat">> -> %%FIXME
            case fxml:get_attr_s(<<"to">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                To ->
                    ToJid = jlib:string_to_jid(To),
                    #jid{luser=ToUser,lserver=ToServer} = ToJid,
                    Pids = get_user_pids(ToUser, ToServer),
                    ?DEBUG(?MODULE_STRING " privchat Sending to ~p, his pids list is: ~p", [ ToUser, Pids ]),
                    Data = fxml:get_attr_s(<<"body">>, Args),
                    %% FIXME we are sending to the process of the user, not the socket
                    %% We could use erlang terms instead of JSON
                    Json = [{<<"message">>, [
                            {<<"type">>,<<"privchat">>},
                            {<<"from">>, [
                                {<<"id">>, StateData#state.userid},
                                {<<"username">>, StateData#state.user}]},
                            {<<"body">>, Data}]}],
                    Me = self(),
                    Body = {plain, Json},
                    lists:foreach( fun( Pid ) ->   
                        Pid ! {route, Me, Pid, Body}
                    end, Pids),
                    fsm_next_state(authorized, StateData)
            end;

        <<"user">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_user(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        <<"contactlist">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_contactlist(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        <<"group">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_group(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        % Handle_state i.e. composing, writing, uploading...
        <<"state">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_state(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        <<"thread">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_thread(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        <<"page">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_page(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        <<"action">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    NewState = handle_action(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, NewState)
            end;

        <<"post">> -> % post destinations are 'thread's
            case fxml:get_attr_s(<<"to">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                To ->
           %          handle_post(To, SeqId, Args, StateData),
           %          fsm_next_state(authorized, StateData)
           %  end;
                    % Split between internals and public properties
                    AllProperties = fxml:get_attr_s(<<"properties">>, Args),
                    { PvProperties, PbProperties } = extract_message_options( AllProperties ),

                    Data = fxml:get_attr_s(<<"data">>, Args),
                    Content = fxml:get_attr_s(<<"content">>, Args),
                    From = jlib:jid_to_string(StateData#state.jid),
                    Json = [{<<"type">>,<<"reaction">>},
                            {<<"from">>, [
                                {<<"id">>, StateData#state.userid},
                                {<<"username">>, StateData#state.user}]},
                            {<<"threadid">>, To},
                            {<<"content">>, Content},
                            {<<"data">>, Data},
                            {<<"properties">>, PbProperties}],
                    
                    #jid{luser=_User, lserver=Host} = StateData#state.jid,
                    ?DEBUG(?MODULE_STRING " post: sending message with options: ~p\n~p", [ PvProperties, Json ]),
                    mod_chat:route(Host, To, From, message, [Json, PvProperties]),

                    fsm_next_state(authorized, StateData)
                end;

        <<"search">> ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle_search(Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end;

        Type ->
            case fxml:get_attr_s(<<"operation">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Operation ->
                    handle(Type, Operation, SeqId, Args, StateData),
                    fsm_next_state(authorized, StateData)
            end

        %_Any ->
        %    ?ERROR_MSG(?MODULE_STRING " Unhandled action: ~p\n~p", [_Any, Args]),
        %    fsm_next_state(authorized, StateData)

    end;

authorized({message, SeqId, Args}, StateData) ->
    case fxml:get_attr_s(<<"type">>, Args) of
        <<"rtcdata">> ->
            case fxml:get_attr_s(<<"to">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                To ->
                    %?DEBUG("fxml: ~p", [ xmlelement("message", Args) ]),
                    %Pids = get_members(To),
                    
                    ToJid = jlib:string_to_jid(To),
                    #jid{luser=ToUser,lserver=ToServer} = ToJid,
                    Pids = get_user_pids(ToUser, ToServer),
                    ?DEBUG(?MODULE_STRING " rtcdata Sending to ~p, pids are: ~p", [ ToUser, Pids ]),
                    %From = jlib:jid_to_string(StateData#state.jid),
                    Data = fxml:get_attr_s(<<"data">>, Args),
                    Json = [{<<"message">>, [
                                {<<"type">>,<<"rtcdata">>},
                                {<<"sequence">>, SeqId},
                                {<<"from">>, [
                                    {<<"id">>, StateData#state.userid},
                                    {<<"username">>, StateData#state.user}]},
                                {<<"data">>, Data}]}],

                    Me = self(),
                    Body = {plain, (Json)},
                    lists:foreach( fun( Pid ) ->   
                        Pid ! {route, Me, Pid, Body}
                    end, Pids),
                    fsm_next_state(authorized, StateData)
            end;


        <<"chat">> -> % chat destinations are 'room's
            case fxml:get_attr_s(<<"to">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                BTo ->
                    case fxml:get_attr_s(<<"body">>, Args) of
                        <<>> ->
                            fsm_next_state(authorized, StateData);

                        Body ->

                            From = StateData#state.user,
                            Json = [{<<"message">>, [
                                        {<<"type">>,<<"chat">>},
                                        {<<"sequence">>, SeqId},
                                        {<<"from">>, [
                                            {<<"username">>, From},
                                            {<<"id">>, StateData#state.userid}]},
                                        {<<"discussionid">>, BTo},
                                        {<<"body">>, Body}]}],

                            %Body = (Json),
                            ?DEBUG(?MODULE_STRING " chat Sending to ~p Data: ~p", [ BTo, Body ]),
                            #jid{lserver=Host} = StateData#state.jid,
                            mod_chat:route(Host, BTo, From, message, Json),

                            fsm_next_state(authorized, StateData)
                    end
             end;

        _Other ->
            fsm_next_state(authorized, StateData)

    end;

authorized({invite, _SeqId, Args}, StateData) ->

    case fxml:get_attr_s(<<"discussionid">>, Args) of 
        <<>> ->
            fsm_next_state(authorized, StateData);

        DiscussionId ->
            case fxml:get_attr_s(<<"id">>, Args) of
                <<>> ->
                    fsm_next_state(authorized, StateData);

                Id -> 
                    ToJid = jlib:string_to_jid(Id),
                    From = StateData#state.jid,
                    %User = StateData#state.user,
                    Jid = jlib:jid_to_string(From),
                    Json = {struct,[{<<"message">>,
                      {struct,[{<<"type">>,<<"invite-on-discussion">>},
                           {<<"from">>, {struct,[
                                {<<"userid">>, StateData#state.userid},
                                {<<"username">>, StateData#state.user}]}},
                           {<<"discussionid">>, DiscussionId}]}}]},

                    % VIC We add the user neverless he accepts or denies...
                    #jid{server=Host} = From,
                    ?DEBUG(?MODULE_STRING " Adding user: ~p to DiscussionId: ~p", [ Id, DiscussionId ]),
                    %mod_chat:route(Host, DiscussionId, Jid, add, [ToJid]),
                    mod_chat:route(Host, DiscussionId, Jid, add, [Id]),

                    #jid{user=ToUser,server=ToServer} = ToJid,
                    case get_user_pids(ToUser, ToServer) of
                        [] ->
                            %User is no longer connected.
                            ?DEBUG(?MODULE_STRING "[~5w] User is not available: ~p@~p", [ ?LINE, ToUser, ToServer ]),
                            fsm_next_state(authorized, StateData);

                        Sessions ->
                            
                            ?DEBUG(?MODULE_STRING " Sessions: ~p", [ Sessions ]),
                            % Sending to the user the message invite-on-discussion
                            % using direct messaging
                            Body = (Json),
                            lists:foreach( fun( Pid ) ->   
                                Pid ! {route, self(), Pid, Body}
                            end, Sessions),

                            % Sending to all rooms participants that a new user 
                            % is waiting to join them
                            Json2 = 
                            {struct,[
                                {<<"message">>, {struct,[
                                {<<"type">>, <<"discussion-presence">>},
                                {<<"action">>, <<"waiting">>},
                                {<<"from">>, {struct,[
                                    {<<"id">>, Id}]}},
                                {<<"discussionid">>, DiscussionId}]}}]},

                            #jid{luser=_User, lserver=Host} = StateData#state.jid,
                            mod_chat:route(Host, DiscussionId, Id, message, [ Json2 ]),

                            fsm_next_state(authorized, StateData)
                end
        end
end;

authorized({Command, SeqId, Args}, StateData) ->
    ?ERROR_MSG(?MODULE_STRING "[~5w] UNHANDLED: Command: ~p, Args: ~p", [?LINE, Command, Args ]),
    Answer = make_answer(SeqId, [{<<"code">>, 404}, {<<"status">>, <<"ok">>}]),
    send_element(StateData, (Answer)),
    fsm_next_state(authorized, StateData);

authorized(timeout, StateData) ->
%    Options = [],
%    proc_lib:hibernate(?GEN_FSM, enter_loop,
%       [MODULE, Options, authorized, StateData]),
%    fsm_next_state(authorized, StateData);
    {stop, normal, StateData};

authorized(closed, StateData) ->
    {stop, normal, StateData};

authorized(Any, StateData) ->
    ?ERROR_MSG(?MODULE_STRING "[~5w] authorized Unhandled: ~p", [?LINE, Any ]),
    fsm_next_state(authorized, StateData).

%%----------------------------------------------------------------------
%% Func: StateName/3
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}
%%----------------------------------------------------------------------
%state_name(Event, From, StateData) ->
%    Reply = ok,
%    {reply, Reply, state_name, StateData}.

%%----------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%%----------------------------------------------------------------------
handle_event({db, set}, StateName, StateData) ->
    case catch mnesia:dirty_read(hyd, node) of
        [{hyd, node, Node}] ->
            put(node, Node),
            fsm_next_state(StateName, StateData#state{
                db = Node});

        [] ->
            ?ERROR_MSG(?MODULE_STRING" hyd node is not set in  Mnesia...\n", []),
            fsm_next_state(StateName, StateData);

        Error ->
            ?ERROR_MSG(?MODULE_STRING" Can't retrieve node from Mnesia: ~p\n", [ Error ]),
            fsm_next_state(StateName, StateData)
    end;

handle_event({db, Node}, StateName, StateData) ->
    put(node, Node),
    fsm_next_state(StateName, StateData);

    
handle_event(_Event, StateName, StateData) ->
    fsm_next_state(StateName, StateData).

%%----------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}
%%----------------------------------------------------------------------
handle_sync_event({get_presence}, _From, StateName, StateData) ->
    User = StateData#state.user,
    PresLast = StateData#state.pres_last,

    Show = get_showtag(PresLast),
    Status = get_statustag(PresLast),
    Resource = StateData#state.resource,

    Reply = {User, Resource, Show, Status},
    fsm_reply(Reply, StateName, StateData);

handle_sync_event(get_subscribed, _From, StateName, StateData) ->
    Subscribed = ?SETS:to_list(StateData#state.pres_f),
    {reply, Subscribed, StateName, StateData};

handle_sync_event(_Event, _From, StateName, StateData) ->
    Reply = ok,
    fsm_reply(Reply, StateName, StateData).

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

%%----------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%%----------------------------------------------------------------------
handle_info({send_text, Text}, StateName, StateData) ->
    send_text(StateData, Text),
    ejabberd_hooks:run(c2s_loop_debug, [Text]),
    fsm_next_state(StateName, StateData);
% handle_info(replaced, _StateName, StateData) ->
%     Lang = StateData#state.lang,
%     send_element(StateData,
% 		 ?SERRT_CONFLICT(Lang, "Replaced by new connection")),
%     send_trailer(StateData),
%     {stop, normal, StateData#state{authenticated = replaced}};

%% Process Packets that are to be send to the user
handle_info({route, From, To, Message}, StateName, StateData) ->
    ?DEBUG(?MODULE_STRING "[~5w] route (~p) from: ~p, To: ~p, message: ~p", [?LINE, StateName, From, To, Message ]),
    case handle_message(Message, From, To, StateData) of
        {ok, Packet} ->
            send_element(StateData, Packet),
            fsm_next_state(StateName, StateData);
        false ->
            fsm_next_state(StateName, StateData)
    end;

handle_info({presence, To, Args}, StateName, StateData) ->
    Type = <<"discussion-presence">>,
    PacketArgs = [ {<<"action">>, <<"here">>} ] ++ Args,
    Data = make_packet(StateData, Type, PacketArgs),
    Packet = (Data),
    ?DEBUG(?MODULE_STRING "[~5w] route presence to pid: ~p: ~p", [?LINE, To, iolist_to_binary(Packet) ]),
    To ! {route, undefined, undefined, Packet},
    fsm_next_state(StateName, StateData);

% initial status, the user {Userid, Username} is just connected, making himself <<"online">>
handle_info({status, Sender, {Userid, Username}, _FromNick}, StateName, StateData) ->

    %?DEBUG(?MODULE_STRING " [~p][STATUS] pres_f: ~p, + ~p (~p)", [ StateData#state.user, ?SETS:to_list(StateData#state.pres_f), Username, Userid ]),

    NewStateData = StateData#state{
        pres_f = ?SETS:add_element(Username, StateData#state.pres_f)
    },

    %?DEBUG(?MODULE_STRING " [~p] User: ~p (~p) is now connected. All my known contacts are: ~p\n", [
    %   StateData#state.user, Username, Userid, 
    %   ?SETS:to_list(NewStateData#state.pres_f) ]),

    send_presence(NewStateData, {Userid, Username}, NewStateData#state.access),

    %?DEBUG(?MODULE_STRING " [PRESENCE] [~p/~p] sending my own presence to him, send_presence/3: ~p,~p", [ 
    %    StateData#state.user, jlib:jid_to_string(StateData#state.jid),
    %    Username, Userid ]),

    % Sending my own presence
    Sender ! {status, StateData#state.userid, StateData#state.user, StateData#state.access},
    fsm_next_state(StateName, NewStateData);

% Receiving status (presence from) from Userid, Username
% Send this information to frontend
handle_info({status, Userid, Username, Status}, StateName, StateData) ->

    %?DEBUG(?MODULE_STRING "[~5w] [~p][STATUS] Received presence from ~p (~p), Status: ~p", [?LINE, StateData#state.user, Username, Userid, Status ]),

    Data = make_presence( StateData, Userid, Username, Status ),

    % ?DEBUG(?MODULE_STRING "[~5w] [~p][STATUS] A Presence packet: ~p", [?LINE, StateData#state.user, Data ]),

    Packet = (Data),
    send_element(StateData, Packet),
    fsm_next_state(StateName, StateData);

handle_info({'DOWN', Monitor, _Type, _Object, _Info}, _StateName, StateData)
  when Monitor == StateData#state.socket_monitor ->
    {stop, normal, StateData};
handle_info(system_shutdown, _StateName, StateData) ->
    send_element(StateData, ?SERR_SYSTEM_SHUTDOWN),
    {stop, normal, StateData};

handle_info({db, SeqId, Result}, StateName, #state{aux_fields=Actions} = State) ->
    %?DEBUG(?MODULE_STRING ".~p DB: SeqId: ~p, Result: ~p", [ ?LINE, SeqId, Result ]),
    case Result of 
        [<<>>] ->
            ?DEBUG(?MODULE_STRING "[~5w] DB: SeqId: ~p, Error: '~p'", [ ?LINE, SeqId, <<>> ]),
            NewActions = lists:keydelete(SeqId, 1, Actions),
            fsm_next_state(StateName, State#state{aux_fields=NewActions});

        {error, _} = Error ->
            ?ERROR_MSG(?MODULE_STRING "[~5w] DB: SeqId: ~p, Error: ~p", [ ?LINE, SeqId, Error ]),
            Packet = make_error(enoent, SeqId, undefined, undefined),
            send_element(State, Packet),
            NewActions = lists:keydelete(SeqId, 1, Actions),
            fsm_next_state(StateName, State#state{aux_fields=NewActions});

        {ok, Response} ->  % there is many response or a complex response
            case db_results:unpack(Response) of
                {ok, Answer} ->
                    ?DEBUG(?MODULE_STRING "[~5w] Async DB: SeqId: ~p, Result: '~p'", [ ?LINE, SeqId, Answer ]),
                    %?DEBUG(?MODULE_STRING "[~5w] DB: SeqId: ~p, Actions: ~p", [ ?LINE, SeqId, lists:keysearch(SeqId, 1, Actions) ]),
                    %Packet = make_result(SeqId, Answer),
                    case lists:keysearch(SeqId, 1, Actions) of
                        {value, {_, [ _Element, read, _Params]}} ->
                            Packet = make_answer(SeqId, 200, Answer),
                            send_element(State, Packet),
                            NewActions = lists:keydelete(SeqId, 1, Actions),
                            fsm_next_state(StateName, State#state{aux_fields=NewActions});

                        {value, {_, [ _Element, _Operation, _Params]}} ->
                            Packet = make_result(SeqId, Answer),
                            send_element(State, Packet),
                            NewActions = lists:keydelete(SeqId, 1, Actions),
                            fsm_next_state(StateName, State#state{aux_fields=NewActions})
                    end;


                {ok, Infos, More} ->
                    ?DEBUG(?MODULE_STRING "[~5w] Async DB: SeqId: ~p, Infos: ~p", [ ?LINE, SeqId, Infos ]),
                    case db_results:unpack(More) of
                        {ok, Answer} ->
                            %?DEBUG(?MODULE_STRING "[~5w] Async DB: SeqId: ~p, Actions: ~p", [ ?LINE, SeqId, lists:keysearch(SeqId, 1, Actions) ]),
                            Packet = make_result(SeqId, Answer),
                            send_element(State, Packet),
                            case lists:keysearch(SeqId, 1, Actions) of
                                {value, {_, [ Element, Operation, Params]}} ->
                                    action_trigger(State, Element, Infos, Operation, Params, Answer),
                                    NewActions = lists:keydelete(SeqId, 1, Actions),
                                    fsm_next_state(StateName, State#state{aux_fields=NewActions});

                                false ->
                                    fsm_next_state(StateName, State)
                            end;

                        {error, Reason} = Error ->
                            ?DEBUG(?MODULE_STRING "[~5w] DB: SeqId: ~p, Error: ~p", [ ?LINE, SeqId, Error ]),
                            Packet = make_error(Reason, SeqId, undefined, undefined),
                            send_element(State, Packet),
                            NewActions = lists:keydelete(SeqId, 1, Actions),
                            fsm_next_state(StateName, State#state{aux_fields=NewActions})
                    end;

                {error, Reason} = Error ->
                    ?DEBUG(?MODULE_STRING "[~5w] DB: SeqId: ~p, Error: ~p", [ ?LINE, SeqId, Error ]),
                    Packet = make_error(Reason, SeqId, undefined, undefined),
                    send_element(State, Packet),
                    NewActions = lists:keydelete(SeqId, 1, Actions),
                    fsm_next_state(StateName, State#state{aux_fields=NewActions})
            end
    end;

%handle_info({force_update_presence, LUser}, StateName,
%            #state{user = LUser, server = LServer} = StateData) ->
%    NewStateData =
%        case StateData#state.pres_last of
%            {xmlelement, "presence", _Attrs, _Els} ->
%                PresenceEl = ejabberd_hooks:run_fold(
%            c2s_update_presence,
%            LServer,
%            StateData#state.pres_last,
%            [LUser, LServer]),
%               StateData2 = StateData#state{pres_last = PresenceEl},
%               presence_update(StateData2#state.jid,
%                       PresenceEl,
%                       StateData2),
%               StateData2;
%            _ ->
%                StateData
%    end,
%    {next_state, StateName, NewStateData};
handle_info({broadcast, Type, From, Packet}, StateName, StateData) ->
    Recipients = ejabberd_hooks:run_fold(
            c2s_broadcast_recipients, StateData#state.server,
            [],
            [StateData, Type, From, Packet]),
    lists:foreach(
        fun(USR) ->
            ejabberd_router:route(
                From, jlib:make_jid(USR), Packet)
        end, lists:usort(Recipients)),
    fsm_next_state(StateName, StateData);
handle_info(Info, StateName, StateData) ->
    ?ERROR_MSG(?MODULE_STRING "[~5w] Unexpected info: ~p", [?LINE, Info]),
    fsm_next_state(StateName, StateData).


%%----------------------------------------------------------------------
%% Func: print_state/1
%% Purpose: Prepare the state to be printed on error log
%% Returns: State to print
%%----------------------------------------------------------------------
print_state(State = #state{pres_t = T, pres_f = F, pres_a = A, pres_i = I}) ->
   State#state{pres_t = {pres_t, ?SETS:size(T)},
               pres_f = {pres_f, ?SETS:size(F)},
               pres_a = {pres_a, ?SETS:size(A)},
               pres_i = {pres_i, ?SETS:size(I)}
               }.
    
%%----------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%%----------------------------------------------------------------------
terminate(_Reason, session_established = StateName, StateData) ->
    ?DEBUG(?MODULE_STRING" Terminate: ~p (~p)\n~p\n", [ _Reason, StateName, StateData ]),
    case StateData#state.authenticated of
        replaced ->
            ?INFO_MSG("(~w) Replaced session for ~s",
                  [StateData#state.socket,
                   jlib:jid_to_string(StateData#state.jid)]),
            From = StateData#state.jid,
            Packet = {xmlelement, "presence",
                  [{"type", "unavailable"}],
                  [{xmlelement, "status", [],
                [{xmlcdata, "Replaced by new connection"}]}]},
            ejabberd_sm:close_session_unset_presence(
              StateData#state.sid,
              StateData#state.user,
              StateData#state.server,
              StateData#state.resource,
              "Replaced by new connection"),
            presence_broadcast(
              StateData, From, StateData#state.pres_a, Packet),
            presence_broadcast(
              StateData, From, StateData#state.pres_i, Packet);

        _ -> % User is not authenticated
            ?INFO_MSG("(~w) Close half-opened session for unauthenticated connection: ~p", [
                StateData#state.socket, StateData#state.jid])
    end,
    (StateData#state.sockmod):close(StateData#state.socket),
    ok;

terminate(_Reason, authorized = _StateName, #state{ authenticated = Authenticated } = StateData) ->
    case Authenticated of
        true ->
            ?INFO_MSG(?MODULE_STRING "[~5w] Close authorized session for SID: ~p, Ressource ~p, Userid: ~p User: ~p Reason: ~p", [
                    ?LINE,
                    StateData#state.sid,
                    StateData#state.resource,
                    StateData#state.userid,
                    StateData#state.user,
                    _Reason
                    ]),

            %% [GTM] Log end of session
            data_specific(StateData, hyd_users, session_end, [ StateData#state.resource, seqid() ]),

            EmptySet = ?SETS:new(),
            case StateData of
                #state{pres_last = undefined,
                    pres_a = EmptySet,
                    pres_i = EmptySet,
                    pres_invis = false} ->

                    ejabberd_sm:close_session(StateData#state.sid,
                            StateData#state.userid,
                            StateData#state.server,
                            StateData#state.resource);
                _ ->
                From = StateData#state.jid,
                     Packet = {xmlelement, "presence",
                         [{"type", "unavailable"}], []},
                         ejabberd_sm:close_session_unset_presence(
                                 StateData#state.sid,
                                 StateData#state.user,
                                 StateData#state.server,
                                 StateData#state.resource,
                                 ""),
                         presence_broadcast(
                                 StateData, From, StateData#state.pres_a, Packet),
                         presence_broadcast(
                                 StateData, From, StateData#state.pres_i, Packet)
            end,
            bounce_messages();

        _ ->
            ok
    end,
    (StateData#state.sockmod):close(StateData#state.socket),
    ok;

terminate(_Reason, StateName, StateData) ->
    ?ERROR_MSG(?MODULE_STRING "[~5w] Closing connection in state: ~p: sid: ~p", [ ?LINE, StateName, StateData#state.sid ]),
    (StateData#state.sockmod):close(StateData#state.socket),
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

send_text(StateData, Text) ->
    Module = StateData#state.sockmod,
    Socket = StateData#state.socket,

    %?DEBUG(?MODULE_STRING " [~s (~p|~p)] Send DATA\n\n", [ StateData#state.user, seqid(), StateData#state.sid ]),
    %?DEBUG("   ~s \n\n", [ Text ]),
    %?DEBUG("   ~p \n\n", [ Text ]),

    Module:send(Socket, Text).
    %(StateData#state.sockmod):send(StateData#state.socket, Text).

send_element(StateData, Element) ->
    seqid(1),   % increment
    send_text(StateData, Element).
    %Json = sockjs_json:encode(Element),
    %send_text(StateData, Json).

%-spec send_packet(
%    StateData::#state{},
%    Type::binary(),
%    Args::list(tuple())) -> ok.

%send_packet(StateData, Type, Args) ->
%    Json = make_packet(StateData, Type, Args),
%    Element = (Json),
%    send_text(StateData, Element).

make_packet(StateData, Type, Args) ->
    [{<<"message">>, [
        {<<"type">>, Type},
        {<<"version">>, 1},
        {<<"from">>, [
            {<<"id">>, StateData#state.userid},
            {<<"username">>, StateData#state.user}
        ]} | Args]}].

%% Copied from ejabberd_socket.erl
%% -record(socket_state, {sockmod, socket, receiver}).

get_conn_type(StateData) ->
    StateData#state.sockmod.


privacy_check_packet(StateData, From, To, Packet, Dir) ->
    ejabberd_hooks:run_fold(
      privacy_check_packet, StateData#state.server,
      allow,
      [StateData#state.user,
       StateData#state.server,
       StateData#state.privacy_list,
       {From, To, Packet},
       Dir]).

presence_broadcast(StateData, From, JIDSet, Packet) ->
    lists:foreach(fun(JID) ->
			  FJID = jlib:make_jid(JID),
			  case privacy_check_packet(StateData, From, FJID, Packet, out) of
			      deny ->
				  ok;
			      allow ->
				  ejabberd_router:route(From, FJID, Packet)
			  end
		  end, ?SETS:to_list(JIDSet)).




% remove_element(E, Set) ->
%     case ?SETS:is_element(E, Set) of
%         true ->
%             ?SETS:del_element(E, Set);
%         _ ->
%             Set
%     end.

get_showtag(undefined) ->
    "unavailable";
get_showtag(Presence) ->
    case fxml:get_path_s(Presence, [{elem, "show"}, cdata]) of
	""      -> "available";
	ShowTag -> ShowTag
    end.

get_statustag(undefined) ->
    "";
get_statustag(Presence) ->
    case fxml:get_path_s(Presence, [{elem, "status"}, cdata]) of
	ShowTag -> ShowTag
    end.

peerip(SockMod, Socket) ->
    IP = case SockMod of
	     gen_tcp -> inet:peername(Socket);
	     _ -> SockMod:peername(Socket)
	 end,
    case IP of
	{ok, IPOK} -> IPOK;
	_ -> undefined
    end.

%% fsm_next_state_pack: Pack the StateData structure to improve
%% sharing.
%fsm_next_state_pack(StateName, StateData) ->
%    fsm_next_state_gc(StateName, pack(StateData)).

%% fsm_next_state_gc: Garbage collect the process heap to make use of
%% the newly packed StateData structure.
%fsm_next_state_gc(StateName, PackedStateData) ->
%    erlang:garbage_collect(),
%    fsm_next_state(StateName, PackedStateData).

%% fsm_next_state: Generate the next_state FSM tuple with different
%% timeout, depending on the future state
fsm_next_state(session_established, StateData) ->
    %seqid(1),
    {next_state, session_established, StateData, ?C2S_HIBERNATE_TIMEOUT};
fsm_next_state(authorized, StateData) ->
    %seqid(1),
    {next_state, authorized, StateData, ?C2S_AUTHORIZED_TIMEOUT};
fsm_next_state(StateName, StateData) ->
    %seqid(1),
    {next_state, StateName, StateData, ?C2S_OPEN_TIMEOUT}.

%% fsm_reply: Generate the reply FSM tuple with different timeout,
%% depending on the future state
fsm_reply(Reply, session_established, StateData) ->
    %seqid(1),
    {reply, Reply, session_established, StateData, ?C2S_HIBERNATE_TIMEOUT};
fsm_reply(Reply, authorized, StateData) ->
    %seqid(1),
    {reply, Reply, authorized, StateData, ?C2S_AUTHORIZED_TIMEOUT};
fsm_reply(Reply, StateName, StateData) ->
    %seqid(1),
    {reply, Reply, StateName, StateData, ?C2S_OPEN_TIMEOUT}.

%% Used by c2s blacklist plugins
is_ip_blacklisted(undefined) ->
    false;
is_ip_blacklisted({IP,_Port}) ->
    ejabberd_hooks:run_fold(check_bl_c2s, false, [IP]).


fsm_limit_opts(Opts) ->
    case lists:keysearch(max_fsm_queue, 1, Opts) of
	{value, {_, N}} when is_integer(N) ->
	    [{max_queue, N}];
	_ ->
	    case ejabberd_config:get_local_option(max_fsm_queue, fun option_check/1) of
		N when is_integer(N) ->
		    [{max_queue, N}];
		_ ->
		    []
	    end
    end.

bounce_messages() ->
    receive
        {route, From, To, El} ->
            ejabberd_router:route(From, To, El),
            bounce_messages()
        after 0 ->
            ok
    end.


% extract(Args) ->
%     lists:foldl( fun({K,V}, {Attrs,Rest} = Acc) ->
%         case is_attr(K) of
%             {true, NewK} ->
%                 NewAttrs = [ {NewK,V} | Attrs ],
%                 NewRest = lists:keydelete(K, 1, Rest),
%                 { NewAttrs, NewRest };
%             _ ->
%                 Acc
%         end
%     end, {[], Args}, Args).

% extract_body(Args) ->
%     case lists:keysearch(<<"body">>, 1, Args) of
%         {value, {_, Value}} ->
%             [{xmlelement, "body", [], [{xmlcdata, Value}]}];
% 
%         _ ->
%             []
%     end.
% 
% is_attr(<<"to">>) -> 
%     {true, "to"};
% is_attr(<<"from">>) -> 
%     {true, "from"};
% is_attr(<<"type">>) -> 
%     {true, "type"};
% is_attr(_) -> 
%     false.

make_error(timeout, Seqid, Code, Description)  ->
    make_error([
        {<<"code">>, <<"500">>},
        {<<"description">>,<<"operation timeout (SRVPB2332)">>}
    ], Seqid, Code, Description);

make_error(enoent, Seqid, Code, Description)  ->
    make_error([
        {<<"code">>, <<"500">>},
        {<<"description">>,<<"invalid operation (SRVPB2338)">>}
    ], Seqid, Code, Description);

make_error(Values, Seqid, _Code, _Description) when is_list(Values) ->
    [ 
        {<<"success">>, <<"false">>},
        {<<"status">>,<<"error">>}, 
        {<<"id">>, Seqid},
        {<<"error">>, Values}
    ];

make_error(Reason, Seqid, Code, Description) ->
    case Reason of 
        {'EXIT', _Rest} ->
            ?ERROR_MSG(?MODULE_STRING " make_error 'EXIT' : ~p", [ _Rest ]),
            make_error(Seqid, Code, Description);

        _ ->
            make_error(Seqid, Code, Description)
    end.

make_error(SeqId, Code, Description) ->
    [
        {<<"success">>, <<"false">>},
        {<<"status">>, <<"error">>}, 
        {<<"id">>, SeqId}, 
        {<<"error">>, [
            {<<"description">>, Description},
            {<<"code">>, Code}
            ]}
    ].


%make_answer(SeqId, Code, Args) ->
%    {struct,[{<<"a">>, [
%        {<<"id">>,SeqId},
%        {<<"code">>, Code},
%        {<<"data">>, Args} 
%    ]}]}.

make_answer(SeqId, Code, []) ->
    [
        {<<"a">>, [
            {<<"id">>,      SeqId},
            {<<"code">>,    Code},
            {<<"success">>, <<"true">>},
            {<<"status">>,  <<"ok">>}
        ]}
    ];
make_answer(SeqId, Code, Args) ->
    [
        {<<"a">>, [
            {<<"id">>,      SeqId},
            {<<"code">>,    Code},
            {<<"success">>, <<"true">>},
            {<<"data">>,    Args} 
        ]}
    ].

make_result(SeqId, true) ->
    make_answer(SeqId, 204, [
        {<<"result">>, <<"true">>}
    ]);
make_result(SeqId, false) ->
    make_answer(SeqId, 204, [
        {<<"result">>, <<"false">>}
    ]);
make_result(SeqId, <<>>) ->
    make_answer(SeqId, 204, [
        {<<"result">>, []}
    ]);
make_result(SeqId, []) ->
    make_answer(SeqId, 204, [
        {<<"result">>, []}
    ]);
make_result(SeqId, Result) when is_tuple(Result) ->
    make_answer(SeqId, 200, [ 
        {<<"result">>, [Result]}
    ]);
make_result(SeqId, Result) when is_binary(Result) ->
    make_answer(SeqId, 200, [ 
        {<<"result">>, Result}
    ]);
make_result(SeqId, [<<>>]) ->
    make_answer(SeqId, 204, [ 
        {<<"result">>, []}
    ]);
make_result(SeqId, [Result]) when is_binary(Result) ->
    make_answer(SeqId, 200, [ 
        {<<"result">>, Result}
    ]);
make_result(SeqId, Result) when is_list(Result) ->
    make_answer(SeqId, 200, [ 
        {<<"result">>, Result}
    ]).

make_answer(SeqId, Args) ->
    [{<<"a">>, [
        {<<"id">>, SeqId},
        {<<"data">>, Args}]
    }].

make_answer_not_found(SeqId) ->
    make_answer(SeqId, 404, [
        {<<"result">>, []}
    ]).

get_user_pids(LUser, LServer) ->
    US = {LUser, LServer},
    %?DEBUG(?MODULE_STRING " Searching key: ~p in session index", [ US ]),
    case catch mnesia:dirty_index_read(session, US, #session.us) of
        {'EXIT', _Reason} ->
            [];
        Ss ->
            [element(2, S#session.sid) || S <- Ss]
    end.

option_check(X) -> 
    X.

handle_configuration(Id, Args, State) ->
    case fxml:get_attr_s(<<"operation">>, Args) of
        <<"set">> ->
           handle_configuration(write, Id, Args, State);

        <<"get">> ->
           handle_configuration(read, Id, Args, State);

       <<"revert">> ->
           handle_configuration(revert, Id, Args, State);

       _ ->
           false
    end.

-spec handle_configuration(
    Mode:: read|write|revert|list,
    Id :: non_neg_integer() | undefined,
    Args :: list() ) -> {term(), #state{}}.

handle_configuration(Mode, Id, Args, State) ->
       case do_configuration(Mode, Id, Args, State) of
           {ok, {_Result, _NewState} = Res} ->
               Res;

           {error, Reason} ->
               {Reason, State}
       end.

-spec do_configuration(
    Mode :: read|write|revert,
    Id :: non_neg_integer(),
    Args :: list(),
    State :: #state{}) -> {ok, {term(),#state{}}} | {error, term()}.

do_configuration(write, Id, Args, State) ->
    case fxml:get_attr_s(<<"value">>, Args) of
        <<>> ->
	        {ok, {false, State}};
	    
	%% Need time to mature this feature
	%% {struct, Data} ->
	%%     ?DEBUG(?MODULE_STRING " Json Object: ~p", [ Data ]),
	%%     profile(State, ?OPERATION_SETREGISTRY_VALUE, [ Id, Data ]),
	%%     {ok, {ok, State}};
	    
        Value -> 
            ?DEBUG("Configuration (write): Id: ~p, Value: ~p", [ Id, Value ]),
            profile(State, ?OPERATION_SETCONFIGURATION_VALUE, [ Id, Value ]),
            {ok, {ok, State}}
    end;

do_configuration(read, Id, _, State) ->
    {ok, {profile(State, ?OPERATION_GETCONFIGURATION_VALUE, Id), State}};

do_configuration(revert, Id, _, State) ->
    {ok, {profile(State, ?OPERATION_RESETCONFIGURATION_VALUE, Id), State}};

do_configuration(list, _, _, State) ->
    Result = do_user(?OPERATION_GETCONFIGURATION, State#state.userid, undefined, undefined, State),
    {ok, {Result, State}};

do_configuration(Mode, Id, Args, _State) ->
    ?ERROR_MSG("Unhandled configuration (default) (~p): Id: ~p, Value: ~p", [ Mode, Id, Args ]),
    ok.

handle_visibility(Id, Args, State) ->
    case fxml:get_attr_s(<<"operation">>, Args) of
       <<"set">> ->
           handle_visibility(write, Id, Args, State);

       <<"get">> ->
           handle_visibility(read, Id, Args, State);

       <<"revert">> ->
           handle_visibility(revert, Id, Args, State);

       _ ->
           false
    end.

% handling visibility i.e. managing what user in a specific category can see 
% FIXME refactoring needed
handle_visibility(Mode, Id, Args, State) ->
       case do_visibility(Mode, Id, Args, State) of
           {ok, {_Result, _NewState} = Res} ->
               Res;

           {error, Reason} ->
               {Reason, State}
       end.

-spec do_visibility(
    Mode :: read|write|revert,
    Id :: non_neg_integer(),
    Args :: list(),
    State :: #state{}) -> {ok, {term(),#state{}}} | {error, term()}.

do_visibility(write, Id, Args, State) ->
    case fxml:get_attr_s(<<"value">>, Args) of
        <<>> ->
            case fxml:get_attr_s(<<"values">>, Args) of
                {struct, Data} ->
                    ?DEBUG(?MODULE_STRING " visibility Data: ~p", [ Data ]),
                    profile(State, ?OPERATION_SETVISIBILITY_VALUE, [ Id, Data ]),
                    {ok, {<<"ok">>, State}};

                Values when is_list(Values) ->
                    ?DEBUG(?MODULE_STRING " visibility Values: ~p", [ Values ]),
                    Proplist = lists:map(
                        fun({struct, [Data]}) ->
                                Data;
                            (Data) when is_binary(Data) ->
                                Data
                        end, Values),
                    ?DEBUG(?MODULE_STRING " visibility Proplist: ~p", [ Proplist ]),
                    profile(State, ?OPERATION_SETVISIBILITY_VALUE, [ Id, Proplist ]),
                    {ok, {<<"ok">>, State}};

                _ ->
                    {ok, {<<"noop">>, State}}
	        end;	
	    
        Value -> 
            ?DEBUG("Visibility (write): Id: ~p, Value: ~p", [ Id, Value ]),
            profile(State, ?OPERATION_SETVISIBILITY_VALUE, [ Id, Value ]),
            {ok, {<<"ok">>, State}}
    end;

do_visibility(read, Id, _, State) ->
    case profile(State, ?OPERATION_GETVISIBILITY_VALUE, Id) of  
        {ok, Result} ->
            {ok, {Result, State}};
        _ ->
            {ok, {[], State}}
    end;
% 
% do_visibility(revert, Id, _, State) ->
%     {ok, {profile(State, ?OPERATION_RESETVISIBILITY_VALUE, Id), State}};

do_visibility(Mode, Id, Args, _State) ->
    ?ERROR_MSG("Unhandled visibility (default) (~p): Id: ~p, Value: ~p", [ Mode, Id, Args ]),
    ok.

initial_presence(StateData, Username, MeNick, Userid) ->

    % may be 'spawned' to accelerate user connection process

    case profile(StateData#state{userid=Userid}, ?OPERATION_GETCONTACTLIST, undefined) of
        {ok, Contacts} ->
            ?DEBUG(?MODULE_STRING " [CONTACTS] ~p registered contacts are: ~p",  [ Username, Contacts ]),
            Domain = StateData#state.server,

            lists:foldl(fun(Contact, Acc) ->
                case get_user_pids(Contact,Domain) of
                    [] ->
                        Acc;
                    Pids ->
                        ?DEBUG(?MODULE_STRING " Sending presence message to contact ~p who has ~p pids: ~p", [ Contact, length(Pids), Pids ]),
                        lists:foreach(fun(Pid) ->
                            Pid ! {status, self(), {Userid, Username}, MeNick}
                            end, Pids),
                        [ Contact | Acc ]
                    end 
                end, [], Contacts);

        [] ->
            [];

        _Error ->
            ?DEBUG(?MODULE_STRING ".(~p) initial_presence Error: ~p", [ ?LINE, _Error ]),
            []
    end.

%online_contact(User, Server) ->
%   case ejabberd_sm:user_resources(User, Server) of
%       [] ->
%           false;
%       Resources ->
%           lists:foldl(fun(Resource, Acc) ->
%               case online_pid(User,Server,Resource) of
%                   false ->
%                       Acc;
%                   Pid ->
%                       ?DEBUG("User: ~p (res: ~p): online: ~p\n", [ User, Resource, Pid ]),
%                       [ Pid | Acc ]
%               end
%           end, [], Resources)
%   end.

%online_pid(User,Server,Resource) ->
%   case ejabberd_sm:get_session_pid( User, Server, Resource ) of
%       none ->
%           false;
%       Pid ->
%           Pid
%   end.

% if the contactlists is 'other' send status to connected people
publish_presence(State, <<"other">> = List, Status ) ->

    Contacts = ?SETS:to_list(State#state.pres_f),
    publish_presence(State, List, Status, Contacts);

%    lists:foreach(fun(Contact) ->
%        case get_user_pids(Contact,Server) of
%            [] ->
%                ok;
% 
%            Pids ->
%                ?DEBUG(?MODULE_STRING " [~s]: publish_presence 'other': presence to ~s@~s's pids: ~p", [
%                    State#state.user,
%                    Contact, Server,
%                    Pids ]),
% 
%                lists:foreach(fun(Pid) ->
%                    Pid ! {status, State#state.userid, State#state.user, Status}
%                end, Pids)
% 
%        end end, ?SETS:to_list(State#state.pres_f));
% 
publish_presence(State, List, Status ) ->

    case data(State, hyd_users, contacts_from_category, [ State#state.userid, List ]) of

        {ok, Contacts} when is_list(Contacts) ->
            publish_presence(State, List, Status, Contacts);

        {ok, Contact} when is_binary(Contact) ->
            publish_presence(State, List, Status, [Contact]);

        _ ->
            ?DEBUG(?MODULE_STRING " [~s]: publish_presence: no user in contaclist: ~p", [ 
                State#state.user, List]),
            ok
    end.

% Effectively send the message to existing pids
publish_presence( #state{server=Server} = State, List, Status, Contacts) ->
    lists:foreach(fun(Contact) ->
        case get_user_pids(Contact,Server) of
            [] ->
                ok;

            Pids ->
                ?DEBUG(?MODULE_STRING " [~s]: publish_presence '~p': presence to ~s@~s's pids: ~p", [
                    State#state.user,
                    List, Contact, Server,
                    Pids ]),

                lists:foreach(fun(Pid) ->
                    Pid ! {status, State#state.userid, State#state.user, Status}
                end, Pids)

           end end, Contacts).

-spec make_presence(
    State :: #state{},
    Jid :: #jid{},
    Nick :: binary(),
    Status :: binary() ) -> tuple().

%make_presence(#state{ userid=Userid, user=Username}, Userid, Username, Status) ->
make_presence(_State, Userid, Username, Status) ->
    %JidString = jlib:jid_to_string(Jid),
    [ {<<"presence">>, [
        {<<"from">>, [
            {<<"id">>, Userid},
            {<<"username">>, Username}]},
        {<<"version">>, 4},
        {<<"status">>, Status}]}].

-spec make_presence(
    State :: #state{},
    UserId :: non_neg_integer(),
    Jid :: #jid{},
    Nick :: binary(),
    Status :: binary() ) -> tuple().

make_presence(_State, UserId, Username, _Nick, Status) ->
    [ {<<"presence">>, [
        {<<"from">>, [
            {<<"id">>, UserId},
            {<<"username">>, Username}]
            },
        {<<"version">>, 5},
        {<<"status">>, Status}]}].

%-spec make_self_presence(
%    State :: #state{},
%    Status :: binary() ) -> tuple().

%make_self_presence(State, Status) ->
%    [ {<<"presence">>, [
%        {<<"from">>, [
%            {<<"id">>, State#state.userid},
%            {<<"username">>, State#state.user}]
%            },
%        {<<"version">>, 2},
%        {<<"status">>, Status}]}].

send_presence(State, {UserId, Username}, Status) ->
    Presence = make_presence(State, UserId, Username, [], Status),
    send_element(State, ( Presence )).

% get_members(Key) ->
%     case pg2:get_members(Key) of
%         {error, Reason} ->
%              ?DEBUG("Error: ~p: ~p", [ Key, Reason]),
%             [];
% 
%          _Any ->
%              _Any
%     end.

handle_chat(Group, _SeqId, Args, State) ->
    ?DEBUG(?MODULE_STRING " handle_chat Chat to: ~p", [ Group ]),
    #jid{luser=_User, lserver=Host} = State#state.jid,
    From = jlib:jid_to_string(State#state.jid),
    mod_chat:route(Host, Group, From, message, Args).

handle_room(<<"start">>, SeqId, Args, State) ->
    case fxml:get_attr_s(<<"id">>, Args) of
        <<>> ->
            false;

        RoomId ->
            % What can we do with the roomID ?
            % A specific room type ?
            ?DEBUG(?MODULE_STRING " Room: New room: ~p", [ RoomId ]),
            #jid{luser=User, lserver=Host} = State#state.jid,
            UserName = binary_to_list(User) ++ "@" ++ binary_to_list(Host),
            Ref = base64:encode(lists:concat(tuple_to_list(os:timestamp()))),
            ?DEBUG(?MODULE_STRING " Creating the room: '~p' on '~p' owner: ~p", [ Ref, Host, UserName ]),
            mod_chat:create_room(Host, RoomId, UserName, Ref, []),
            Answer = make_answer(SeqId, [{<<"id">>, Ref}]),
            send_element(State, (Answer))
    end;

handle_room(<<"stop">>, SeqId, Args, State)->
    case fxml:get_attr_s(<<"id">>, Args) of
        <<>> ->
            false;

        Ref ->
            ?DEBUG(?MODULE_STRING " Room: stop: ~p", [ Ref ]),
            #jid{lserver=Host} = State#state.jid,
            From = jlib:jid_to_string(State#state.jid),
            mod_chat:route(Host, Ref, From, stop, []),
            Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
            send_element(State, (Answer))
    end;

handle_room(Operation, _SeqId, Args, _State) ->
    ?DEBUG(?MODULE_STRING " Room (default): Operation: ~p, Args: ~p", [ Operation, Args ]).

handle_quizz(<<"start">>, SeqId, Args, State) ->
    case fxml:get_attr_s(<<"id">>, Args) of
         <<>> ->
            false;

        GameID ->
            ?DEBUG("Quizz: New game: ~p", [ GameID ]),
            % create the new game using the GameID
            % join the game
            %GamePid = game_master:start_link(GameID), % Must starts child, then map a specific ID for this child
            %game
            %Game = 
            %Host = <<"harmony">>,
            #jid{luser=User, lserver=Host} = State#state.jid,
            UserName = binary_to_list(User) ++ "@" ++ binary_to_list(Host),
            GameRef = base64:encode(term_to_binary(os:timestamp())),
            ?DEBUG("Creating the game: '~p' on '~p' owner: ~p", [ GameRef, Host, UserName ]),
            %From = State#state.user,
            mod_game:create_room(Host, GameID, UserName, GameRef, []),
            mod_game:route(Host, GameRef, self(), add, [iolist_to_binary([User, "@", Host])]),

            Answer = make_answer(SeqId, [{<<"id">>, GameRef}]),
            send_element(State, (Answer))

    end;

handle_quizz(<<"ready">>, SeqId, Args, State) ->
    case fxml:get_attr_s(<<"id">>, Args) of
         <<>> ->
            false;

        GameRef ->
            ?DEBUG("Quizz: Ready game: ~p", [ GameRef ]),
            % send the start signal to the game
            #jid{lserver=Host} = State#state.jid,
            mod_game:route(Host, GameRef, self(), game, []),
            mod_game:route(Host, GameRef, self(), next, []),
            Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
            send_element(State, (Answer))

    end;

handle_quizz(<<"stop">>, SeqId, Args, State)->
    case fxml:get_attr_s(<<"id">>, Args) of
	[] ->
	    false;

	GameRef ->
	    ?DEBUG("Quizz: stop game: ~p", [ GameRef ]),
	    #jid{lserver=Host} = State#state.jid,
	    mod_game:route(Host, GameRef, self(), stop, []),
	    Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
	    send_element(State, (Answer))
    end;
handle_quizz(<<"accept">>, SeqId, Args, State)->
    case fxml:get_attr_s(<<"id">>, Args) of
        <<>> ->
            false;

        GameRef ->
            ?DEBUG("Quizz: ~p accepted game: ~p", [ State#state.jid, GameRef ]),
            % join the game
            #jid{luser=User, lserver=Host} = State#state.jid,
            mod_game:route(Host, GameRef, self(), add, [iolist_to_binary([User,"@",Host])]),
            Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
            send_element(State, (Answer))
    end;
handle_quizz(<<"refuse">>, SeqId, Args, State)->
    case fxml:get_attr_s(<<"id">>, Args) of
	[] ->
	    false;

	GameRef ->
	    ?DEBUG("Quizz: ~p refused game: ~p", [ State#state.jid, GameRef ]),
	    Answer = make_answer(SeqId, [{<<"status">>, <<"ok">>}]),
	    send_element(State, (Answer))

    end;
handle_quizz(<<"answer">>, SeqId, Args, State)->
    case fxml:get_attr_s(<<"id">>, Args) of
        <<>> ->
            false;

        GameRef ->
            do_quizz(?OPERATION_ANSWER, GameRef, SeqId, Args, State)

    end;

handle_quizz(<<"next">>,  SeqId, Args, State) ->
    case fxml:get_attr_s(<<"id">>, Args) of
        <<>> ->
            false;

        GameRef ->
            do_quizz(?OPERATION_NEXT, GameRef, SeqId, Args, State)
    end;

handle_quizz(<<"score">>, SeqId, Args, State) ->
    case fxml:get_attr_s(<<"id">>, Args) of
        <<>> ->
            false;

        GameRef ->
            do_quizz(?OPERATION_SCORE, GameRef, SeqId, Args, State)
    end;

handle_quizz(Operation, _SeqId, Args, _State) ->
    ?ERROR_MSG(?MODULE_STRING "Quizz (default): Operation: ~p, Args: ~p", [ Operation, Args ]).

do_quizz(?OPERATION_SCORE, GameRef, _SeqId, _Args, State) ->
    #jid{luser=_User, lserver=Host} = State#state.jid,
    %Player = iolist_to_binary([User, "@", Host]),
    mod_game:route(Host, GameRef, self(), score, [] );

do_quizz(?OPERATION_NEXT, GameRef, _SeqId, _Args, State) ->
    #jid{luser=_User, lserver=Host} = State#state.jid,
    %Player = iolist_to_binary([User, "@", Host]),
    mod_game:route(Host, GameRef, self(), next, [] );
    
do_quizz(?OPERATION_ANSWER, GameRef, _SeqId, Args, State) ->
    case fxml:get_attr_s(<<"value">>, Args) of
        <<>> ->
            false;

        Value ->
            ?DEBUG(?MODULE_STRING "Quizz: ~p next game: ~p, value: ~p", [ State#state.jid, GameRef, Value ]),
            % send this response to the game
            #jid{luser=User, lserver=Host} = State#state.jid,
            Player = iolist_to_binary([User, "@", Host]),
            mod_game:route(Host, GameRef, self(), answer, [ Player, Value ])
    end;

do_quizz(_, _, _, _, _) ->
    ok.

handle_user(Operation, SeqId, Args, State) ->
    case user_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING ".~p handle_user User (default): Operation: ~p, Args: ~p", [ ?LINE, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_user(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_user returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, Answer);

                false -> % error is handled by the operation
                    ok;

                true ->
                    Answer = make_answer(SeqId, 202, []),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_user error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(Reason, SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                {ok, []} ->
                    Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
                    send_element(State, (Answer));

                {ok, true} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"true">>}
                    ]),
                    send_element(State, (Answer));

                {ok, false} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"false">>}
                    ]),
                    send_element(State, (Answer));
                    
                {ok, Result} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer));

                Result ->
                    ?ERROR_MSG(?MODULE_STRING " handle_user returns: ~p", [Result]),
                    %Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                    Answer = make_answer(SeqId, 202, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer))
            end
    end.
    
%handle_user(Operation, _SeqId, Args, _State) ->
%    ?DEBUG("User (default): Operation: ~p, Args: ~p", [ Operation, Args ]).

user_operations(<<"del">>) -> ?OPERATION_DELETEINFO;
user_operations(<<"set">>) -> ?OPERATION_SETINFO;
user_operations(<<"sync">>) -> sync;
user_operations(<<"info">>) -> ?OPERATION_GETCONTACTINFO;
user_operations(<<"tree">>) -> ?OPERATION_GETOTHERCONTACTTREE;
user_operations(<<"infos">>) -> ?OPERATION_GETALLINTERNALDATA;
user_operations(<<"about">>) -> ?OPERATION_ABOUT;
user_operations(<<"label">>) -> ?OPERATION_SETLABEL;
user_operations(<<"cancel">>) -> ?OPERATION_CANCEL;
user_operations(<<"labels">>) -> ?OPERATION_GETLABELS;
user_operations(<<"validate">>) -> ?OPERATION_VALIDATE;
user_operations(<<"contract">>) -> ?OPERATION_CONTRACT;
user_operations(<<"visibility">>) -> ?OPERATION_SETVISIBILITY;
user_operations(<<"getuserinfo">>) -> ?OPERATION_GETUSERINFOS;
user_operations(<<"getschedule">>) -> ?OPERATION_GETSCHEDULE;
user_operations(<<"getproperties">>) -> ?OPERATION_GETPROPERTIES;
user_operations(<<"getconfiguration">>) -> ?OPERATION_GETCONFIGURATION;
user_operations(_) -> false.

do_user(sync, _User, _SeqId, Args, State) ->
    case args(Args, [<<"property">>]) of
        [ Property ] ->
            Data = [{<<"message">>, [
                        {<<"type">>,<<"sync">>},
                        {<<"property">>, Property}]
                }],
            send_element(State, (Data)),
            false;

        _ ->
            []
    end;

do_user(?OPERATION_GETUSERINFOS, User, SeqId, Args, State) ->
    case args(Args, [<<"contactid">>]) of
        [ _ContactId ] = Params ->
            case contacts(State, ?OPERATION_GETUSERINFOS, User, Params) of
                {ok, Result} ->
                    Result;

                _ ->
                    []
            end;

        [] ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(?OPERATION_ABOUT = Op, _User, SeqId, Args, State) ->
    case args(Args, [<<"userid">>, <<"section">>, <<"field">>]) of
        [ _Userid, _Section, _Field ] = Params ->
            profile( State, Op, Params); 

        [ _Userid, _Section ] = Params ->
            profile( State, Op, Params); 

        [ _Userid ] = Params ->
            profile( State, Op, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(?OPERATION_GETALLINTERNALDATA, User, _SeqId, _Args, State) ->
    case profile(State, ?OPERATION_GETALLINTERNALDATA, User) of
        [] ->
            [];

        {ok, Result} ->
            Result
    end;

do_user(?OPERATION_GETLABELS = Op, _User, SeqId, Args, State) ->
    case args(Args, [<<"section">>, <<"field">>]) of
	    [ _Section, _Field ] = Params ->
            profile(State, Op, Params);
            % case profile(State, Op, Params) of
            %     [] ->
            %         [];

            %     {ok, Result} ->
            %         Result
            % end;

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(?OPERATION_GETPROPERTIES, _User, _SeqId, Args, State) ->
    Type = case fxml:get_attr_s(<<"category">>, Args) of
        <<>> ->
            undefined;

        Any ->
            binary_to_list(Any)
    end,
    case profile(State, ?OPERATION_GETPROPERTIES, Type) of
        [] ->
            [];

        {ok, Result} ->
            Result
    end;


do_user(?OPERATION_GETCONFIGURATION, User, _SeqId, _Args, State) ->
    case profile(State, ?OPERATION_GETCONFIGURATION, User) of
        [] ->
            [];

        {ok, Result} ->
            Result
    end;

do_user(?OPERATION_GETOTHERCONTACTTREE = Op, _User, SeqId, Args, State) ->
    case args(Args, [<<"userid">>]) of
        [ OtherId ] ->
            profile(State, Op, [ OtherId ]);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing userid">>),
            send_element(State, Answer),
            false
    end;

do_user(?OPERATION_GETCATEGORIES, User, _SeqId, _Args, State) ->
    profile(State, ?OPERATION_GETCATEGORIES, User);

do_user(Op = ?OPERATION_GETCONTACTINFO, _User, SeqId, Args, State) ->
    case args(Args, [<<"section">>, <<"field">>, <<"index">>]) of
        [ _Section, _Field, _Index ] = Params ->
            profile(State, Op, Params);

        [ _Section, _Field ] = Params ->
            profile(State, Op, Params);

        [ _Section ] = Params ->
            profile(State, Op, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(Op = ?OPERATION_SETINFO, _User, SeqId, Args, State) ->
    ?DEBUG("do_user: Args: ~p", [ Args ]),
    case args(Args, [<<"section">>, <<"values">>, <<"field">>, <<"index">>, <<"contract">> ]) of
        [ Section, {struct, Values} ] ->
            profile(State, Op, [ Section, Values ]);

        [ Section, {struct, Values}, Field ] -> % Create a new multiple field instance
            profile(State, Op, [ Section, Values, Field ]);

        [ Section, {struct, Values}, Field, Index ] -> % Update an existing multiple field instance
            profile(State, Op, [ Section, Values, Field, Index ]);

        [ Section, {struct, Values}, Field, Index, Contract ] -> % May update an existing multiple field instance
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            profile(State, ?OPERATION_SETINFO_TMP, [ Section, Values, Field, Index, Temporary]);

        [ Section, Value, Field, Index ] -> % Set a specific value for an existing multiple field instance
            profile(State, Op, [ Section, Value, Field, Index ]);

        [ Section, Value, Field, Index, Contract ] -> % Set a specific value for an existing multiple field instance
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            profile(State, ?OPERATION_SETINFO_TMP, [ Section, Value, Field, Index, Temporary]);

        _Wrong ->
            ?ERROR_MSG(?MODULE_STRING ".~p do_user: extracted: ~p", [ ?LINE, _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(Op = ?OPERATION_DELETEINFO, _User, SeqId, Args, State) ->
    ?DEBUG("do_user: Args: ~p", [ Args ]),
    case args(Args, [<<"section">>, <<"field">>, <<"index">>, <<"contract">> ]) of
        [ _Section, _Field, _Index ] = Params ->
            profile(State, Op, Params);

        [ Section, Field, Index, Contract ] = _Params ->
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            profile(State, Op, [ Section, Field, Index, Temporary ]);

        [ _Section, _Field ] = Params ->
            profile(State, Op, Params);

        _Wrong ->
            ?ERROR_MSG("do_user: args: ~p", [ _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;


do_user(Op = ?OPERATION_SETLABEL, _User, SeqId, Args, State) ->
    ?DEBUG("do_user: set_label Args: ~p", [ Args ]),
    case args(Args, [<<"section">>, <<"field">>, <<"index">>, <<"label">> ]) of
        [ _Section, _Field, _Index, _Label ] = Params ->
            profile(State, Op, Params);

        _Wrong ->
            ?ERROR_MSG("do_user: set_label extracted: ~p", [ _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(Op = ?OPERATION_SETVISIBILITY, _User, SeqId, Args, State) ->
    ?DEBUG(?MODULE_STRING "do_user: Args: ~p", [ Args ]),
    case args(Args, [<<"section">>, <<"field">>, <<"index">>, <<"value">>, <<"contract">> ]) of
        [ _Section, _Field, _Index, _Value ] = Params ->
            profile(State, Op, Params);

        [ Section, Field, Index, Value, Contract ] -> % May update an existing multiple field instance
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            profile(State, ?OPERATION_SETVISIBILITY_TMP, [ Section, Field, Index, Value, Temporary ]);

        _Wrong ->
            ?ERROR_MSG(?MODULE_STRING ".~p do_user: extracted: ~p", [ ?LINE, _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_user(Op, _User, SeqId, Args, State) when
    Op =:= ?OPERATION_CANCEL;
    Op =:= ?OPERATION_VALIDATE ->

    case args(Args, [<<"contract">>]) of
        [ Contract ] ->
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            profile(State, Op, [ Temporary ]);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing argument: contract">>),
            send_element(State, (Answer)),
            false
    end;

do_user(?OPERATION_CONTRACT = Op, _User, SeqId, Args, State) ->
    case args(Args, [<<"contract">>, <<"section">>, <<"field">>, <<"index">>]) of
        [ Contract, Category, Field, Index ] ->
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            profile(State, Op,  [ Temporary, Category, Field, Index ]);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: (contract, section, field, index)">>),
            send_element(State, (Answer)),
            false
    end;

do_user(_Operation, _User, _SeqId, _Args, _State) ->
    ?ERROR_MSG("DEFAULT(~p): do_user ~p: Operation: ~p, Seqid: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    {error, enoent}.

handle_contact(Operation, SeqId, Args, State) ->
    case contact_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING ".~p handle_contact Contact (default): Operation: ~p, Args: ~p", [?LINE, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_contact(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_contact returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, Answer);

                false -> % error is handled by the operation
                    ok;

                true -> % FIXME dead code ?
                    Answer = make_answer(SeqId, [
                        {<<"result">>, <<"ok">>}
                    ]),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_contact error: ~p on ~p seqid: ~p", [ ?LINE, Reason, Operation, SeqId ]),
                    Answer = make_error(Reason, SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                %% {ok, []} ->
                %%     Answer = make_answer(SeqId, 201, []),
                %%     send_element(State, (Answer));

                {ok, Result} ->
                    ?DEBUG(?MODULE_STRING " handle_contact returns: ~p", [Result]),
                    Answer = make_result(SeqId, Result),
                    send_element(State, Answer)

                % Result ->
                %     ?DEBUG(?MODULE_STRING " handle_contact returns: ~p", [Result]),
                %     %Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                %     Answer = make_answer(SeqId, 202, [
                %         {<<"result">>, Result}
                %     ]),
                %     send_element(State, (Answer))
            end
    end.

contact_operations(<<"del">>) -> ?OPERATION_DELETECONTACT;
contact_operations(<<"set">>) -> ?OPERATION_SETINFO;
contact_operations(<<"info">>) -> ?OPERATION_GETCONTACTINFO;
contact_operations(<<"list">>) -> ?OPERATION_GETCONTACTLIST;
contact_operations(<<"tree">>) -> ?OPERATION_GETCONTACTTREE;
contact_operations(<<"block">>) -> ?OPERATION_BLOCKCONTACT;
contact_operations(<<"label">>) -> ?OPERATION_SETLABEL;
contact_operations(<<"accept">>) -> ?OPERATION_ACCEPTCONTACT;
contact_operations(<<"cancel">>) -> ?OPERATION_CANCEL;
contact_operations(<<"labels">>) -> ?OPERATION_GETLABELS;
contact_operations(<<"invite">>) -> ?OPERATION_INVITECONTACT;
contact_operations(<<"refuse">>) -> ?OPERATION_REFUSEINVITATION;
contact_operations(<<"infobis">>) -> ?OPERATION_GETCONTACTINFOBIS;
contact_operations(<<"blocked">>) -> ?OPERATION_LISTBLOCKED;
contact_operations(<<"unblock">>) -> ?OPERATION_UNBLOCKCONTACT;
contact_operations(<<"favorite">>) -> ?OPERATION_ISFAVORITE;
contact_operations(<<"validate">>) -> ?OPERATION_VALIDATE;
contact_operations(<<"addcontact">>) -> ?OPERATION_ADDCONTACT;
contact_operations(<<"invitations">>) -> ?OPERATION_GETINVITATIONS;
contact_operations(<<"fromcategory">>) -> ?OPERATION_GETCONTACTSFROMCATEGORY;
contact_operations(<<"getcategories">>) -> ?OPERATION_GETCATEGORIES;
contact_operations(<<"addcontactincategory">>) -> ?OPERATION_ADDCONTACTINCATEGORY;
contact_operations(_) -> false.

% to be merge with code below
do_contact(Op, User, SeqId, Args, State) when
    Op =:= ?OPERATION_ADDCONTACT ->
    case args(Args, [<<"contactid">>]) of
        [ _ContactId ] = CallArgs ->
            contacts(State, Op, User, CallArgs);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(Op, User, SeqId, Args, State) when
    Op =:= ?OPERATION_LISTBLOCKED ->
    case args(Args, [<<"contactid">>]) of
        [] -> 
            contacts(State, Op, User, []);

        [ _ContactId ] = CallArgs ->
            contacts(State, Op, User, CallArgs);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_INVITECONTACT = Op, User, SeqId, Args, State) ->
    Params = case args(Args, [<<"userid">>]) of
        [ _Userid ] = _Args ->
            _Args;
            
        _ ->
            false
    end,
    case Params of 
        false ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, Answer),
            false;

        [ Userid ] ->
            Do = fun() ->
                contacts(State, Op, User, Params)
            end,
            Success = fun() ->
                Application = <<"com.harmony.contacts">>,
                Title = <<"Contact">>,
                Text = <<>>,
                notification(State, Op, Args, Userid, Application, Title, Text),
                true
            end,
            ok(Do, Success)
    end;

do_contact(Op, User, SeqId, Args, State) when 
    Op =:= ?OPERATION_BLOCKCONTACT;
    Op =:= ?OPERATION_ISFAVORITE;
    Op =:= ?OPERATION_UNBLOCKCONTACT ->
    case args(Args, [<<"contactid">>]) of
        [ _Userid ] = Params ->
            contacts(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;
do_contact(Op, User, SeqId, Args, State) when 
    Op =:= ?OPERATION_ACCEPTCONTACT;
    Op =:= ?OPERATION_REFUSEINVITATION ->
    case args(Args, [<<"contactid">>]) of
        [ _Userid ] = Params ->
            Do = fun() ->
                contacts(State, Op, User, Params)
            end,
            Success = fun() ->
                Application = <<"com.harmony.contacts">>,
                Title = <<"Contact">>,
                Text = <<>>,
                notification(State, Op, Args, _Userid, Application, Title, Text),
                true
            end,
            ok(Do, Success);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(Op, User, SeqId, Args, State) when 
    Op =:= ?OPERATION_DELETECONTACT ->
    case args(Args, [<<"contactid">>, <<"section">>, <<"field">>, <<"index">>]) of
        [ _Contactid, _Section, _Field, _Index ] = Params -> % specific value for field
            contacts(State, ?OPERATION_DELETECONTACTINFO, User, Params);

        [ _Contactid, _Section, _Field ] = Params -> % every values of field
            contacts(State, ?OPERATION_DELETECONTACTINFO, User, Params);

        [ _Contactid, _Section ] = Params -> % everything from section
            contacts(State, ?OPERATION_DELETECONTACTINFO, User, Params);

        [ _Contactid ] = Params -> % remove the contact
            Do = fun() ->
                contacts(State, Op, User, Params)
            end,
            Success = fun() ->
                Application = <<"com.harmony.contacts">>,
                Title = <<"Contact">>,
                Text = <<>>,
                notification(State, Op, Args, _Contactid, Application, Title, Text),
                true
            end,
            ok(Do, Success);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(Op, User, SeqId, Args, State) when
    Op =:= ?OPERATION_GETCONTACTSFROMCATEGORY;
    Op =:= ?OPERATION_GETINVITATIONS ->
    case args(Args, [<<"category">>]) of
        [ _Category ] = Params ->
            contacts(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing argument: category">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_ADDCONTACTINCATEGORY, User, SeqId, Args, State) ->
    case args(Args, [<<"contactid">>,<<"category">>]) of
        [ _ContactId, _Category ] = CallArgs ->
            contacts(State, ?OPERATION_ADDCONTACTINCATEGORY, User, CallArgs);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_GETCONTACTTREE = Op, User, SeqId, _Args, State) ->
    case contacts(State, Op, User, []) of
        [] ->
            [];

        {ok, Result} ->
            %Answer = make_result(SeqId, Result), % To be applied later
            Answer = make_answer(SeqId, [{<<"result">>, Result}]),
            send_element(State, Answer),
            false
    end;

do_contact(?OPERATION_GETCATEGORIES = Op, User, _SeqId, _Args, State) ->
    contacts(State, Op, User, []);

do_contact(?OPERATION_GETCONTACTLIST = Op, User, _SeqId, Args, State) ->
    case args(Args, [<<"category">>]) of
        [ _Category ] = Params ->
            contacts(State, Op, User, Params);

        _ ->
            contacts(State, Op, User, [])

    end;

do_contact(?OPERATION_GETCONTACTINFO = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"contactid">>, <<"section">>, <<"field">>, <<"index">>]) of
        [ _Contactid, _Section, _Field, _Index ] = Params ->
            contacts(State, Op, User, Params);

        [ _Contactid, _Section, _Field ] = Params ->
            contacts(State, Op, User, Params);

        [ _Contactid, _Section ] = Params ->
            contacts(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_GETCONTACTINFOBIS = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"contactid">>, <<"section">>, <<"field">>, <<"index">>]) of
        [ _Contactid, _Section, _Field, _Index ] = Params ->
            contacts(State, Op, User, Params);

        [ _Contactid, _Section, _Field ] = Params ->
            contacts(State, Op, User, Params);

        [ _Contactid, _Section ] = Params ->
            contacts(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_GETLABELS = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"section">>, <<"field">>]) of
        [ _Section, _Field ] = Params ->
            contacts(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_SETINFO = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"contactid">>, <<"section">>, <<"values">>, <<"field">>, <<"index">>, <<"contract">> ]) of
        [ Contactid, Section, {struct, Values} ] ->
            contacts(State, Op, User, [ Contactid, Section, Values ]);

        [ Contactid, Section, {struct, Values}, Field ] ->
            contacts(State, Op, User, [ Contactid, Section, Values, Field ]);

        [ Contactid, Section, {struct, Values}, Field, Index ] ->
            contacts(State, Op, User, [ Contactid, Section, Values, Field, Index ]);

        [ Contactid, Section, {struct, Values}, Field, Index, Contract ] ->
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            contacts(State, ?OPERATION_SETINFO_TMP, User, [ Contactid, Section, Values, Field, Index, Temporary ]);

        [ Contactid, Section, Value, Field, Index ] ->
            contacts(State, Op, User, [ Contactid, Section, Value, Field, Index ]);

        [ Contactid, Section, Value, Field, Index, Contract ] ->
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            contacts(State, ?OPERATION_SETINFO_TMP, User, [ Contactid, Section, Value, Field, Index, Temporary ]);

        _Wrong ->
            ?ERROR_MSG(?MODULE_STRING ".~p do_contact: extracted: ~p", [ ?LINE, _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(?OPERATION_SETLABEL = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"contactid">>, <<"section">>, <<"field">>, <<"index">>, <<"value">> ]) of
        [ _Contactid, _Section, _Field, _Index, _Label ] = Params ->
            contacts(State, Op, User, Params);

        _Wrong ->
            ?ERROR_MSG("do_contact: set_label extracted: ~p", [ _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_contact(Op, User, SeqId, Args, State) when
    Op =:= ?OPERATION_CANCEL;
    Op =:= ?OPERATION_VALIDATE ->
    case args(Args, [<<"contract">>]) of
        [ Contract ] ->
            Temporary = iolist_to_binary([Contract, State#state.resource]),
            contacts(State, Op, User, [ Temporary ]);

        _ ->
            case args(Args, [<<"contactid">>]) of
                [ Contactid ] when Op =:= ?OPERATION_CANCEL ->
                    contacts(State, ?OPERATION_CANCELINVITATION, User, [ Contactid ]);

                _ ->
                    Answer = make_error(SeqId, 406, <<"bad arguments: contract or contactid">>),
                    send_element(State, (Answer)),
                    false
            end
    end;

do_contact(Operation, User, SeqId, Args, _) ->
    ?DEBUG("DEFAULT(~p): do_contact ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, User, Operation, SeqId, Args ]),
    {error, enoent}.

profile_operations(<<"del">>) -> ?OPERATION_DELETEPROFILE;
profile_operations(<<"get">>) -> ?OPERATION_GETPROFILE;
profile_operations(<<"set">>) -> ?OPERATION_SETPROFILE;
profile_operations(<<"tree">>) -> ?OPERATION_GETPROFILETREE;
profile_operations(<<"list">>) -> ?OPERATION_GETPROFILELIST;
profile_operations(<<"store">>) -> ?OPERATION_STOREPROFILE;
profile_operations(<<"restore">>) -> ?OPERATION_RESTOREPROFILE;
profile_operations(<<"presence">>) -> ?OPERATION_SETPROFILEPRESENCE;
profile_operations(_) -> false.

handle_profile(Operation, SeqId, Args, State) ->
    case profile_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING ".~p handle_profile Profile (default): Operation: ~p, Args: ~p", [?LINE, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_profile(OperationId, User, SeqId, Args, State) of
                [] = Empty->
                    ?DEBUG(?MODULE_STRING " handle_profile returns empty", Empty),
                    Answer = make_result(SeqId, Empty),
                    send_element(State, (Answer));

                error -> % error is handled by the operation
                     ok;

                % true ->
                %     Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                %     send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_profile error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                {ok, Result} ->
                    ?DEBUG(?MODULE_STRING " handle_profile returns: ~p", [Result]),
                    Answer = make_result(SeqId, Result),
                    send_element(State, (Answer))
            end
    end.

do_profile(?OPERATION_STOREPROFILE, _User, SeqId, Args, State) ->
    ?DEBUG(?MODULE_STRING " Args: ~p", [ Args ]),
    case args(Args, [<<"category">>,<<"values">>]) of
        [ Category, [{struct, Values}] ] ->
            case profile(State, ?OPERATION_STOREPROFILE, [ Category, Values ]) of
                {ok, _Result} ->
                    {ok, true};

                Error ->
                    {error, Error}
            end;

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            error
        end;

do_profile(Op, _User, SeqId, Args, State) when
    Op =:= ?OPERATION_RESTOREPROFILE;
    Op =:= ?OPERATION_DELETEPROFILE ->
    case args(Args, [ <<"profile">>, <<"contactlist">>]) of
        [ _Profile ] = Params ->
            profile(State, Op, Params);

        [ _Profile, _Contactlist ] = Params ->
            profile(State, ?OPERATION_DELPROFILECATEGORY, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing argument">>),
            send_element(State, (Answer)),
            error
    end;

do_profile(Op, _User, _SeqId, _Args, State) when
    Op =:= ?OPERATION_GETPROFILELIST;
    Op =:= ?OPERATION_GETPROFILETREE ->
    profile(State, Op, []);

do_profile(?OPERATION_SETPROFILEPRESENCE, _User, SeqId, Args, State) ->
    case args(Args, [<<"profile">>,<<"category">>,<<"value">>]) of
        [ _Profile, _Category, _Value ] = Params ->
            case profile(State, ?OPERATION_SETPROFILEPRESENCE, Params) of
                {ok, []} ->
                    {ok, true};

                Error ->
                    {error, Error}
            end;

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            error
    end;

do_profile(?OPERATION_SETPROFILE, _User, SeqId, Args, State) ->
    case args(Args, [<<"profile">>,<<"contactlist">>,<<"value">>]) of
        [ _Profile, _Category, _Value ] = Params ->
            case profile(State, ?OPERATION_SETPROFILE, Params) of
                {ok, []} ->
                    {ok, true};

                {ok, Result} -> % Returns the current version number 
                    {ok, Result};

                Error ->
                    {error, Error}
            end;

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            error
    end;

do_profile(?OPERATION_GETPROFILE = Op, _User, SeqId, Args, State) ->
    case args(Args, [ <<"profile">> ]) of
        [ _Profile ] = Params ->
            profile(State, Op, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            error
    end;

do_profile(_, _, _, _, _) ->
    ok.

handle_group(Operation, SeqId, Args, State) ->
    case group_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING ".~p handle_group Group (default): Operation: ~p, Args: ~p", [ ?LINE, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_group(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_group returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, (Answer));

                false -> % error is handled by the operation
                    ok;

                true ->
                    Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                    send_element(State, (Answer));

                {ok, []} ->
                    Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
                    send_element(State, (Answer));
                    
                {ok, true} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"true">>}
                    ]),
                    send_element(State, (Answer));

                {ok, false} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"false">>}
                    ]),
                    send_element(State, (Answer));
                    
                {ok, Result} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_group error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                Result ->
                    ?ERROR_MSG(?MODULE_STRING " handle_group returns: ~p", [Result]),
                    Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                    send_element(State, (Answer))
            end
    end.

group_operations(<<"list">>) -> ?THREAD_LIST;
group_operations(_) -> false.

do_group(Op, User, _SeqId, _Args, State) when 
    Op =:= ?THREAD_LIST ->

    group(State, Op, User, undefined);

do_group(Op, User, SeqId, Args, State) when 
    Op =:= ?THREAD_BOUNDS;
    Op =:= ?THREAD_SUBSCRIBERS ->

    case args(Args, [<<"id">>]) of
        [ _Id ] = Params ->
            case group(State, Op, User, Params) of
                [] ->
                    [];

                {ok, Result} ->
                    Result
            end;

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: id">>),
            send_element(State, (Answer)),
            false
    end;

do_group(_Operation, _User, _SeqId, _Args, _State) ->
    ?DEBUG("DEFAULT(~p): do_group ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

group(#state{userid=Userid} = State, ?THREAD_LIST, _User, _) ->
    data_specific(State, hyd_users, groups, [ Userid ]);

group(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): Group ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, Userid, Operation, User, Args ]),
    {error, enoent}.

handle_thread(Operation, SeqId, Args, State) ->
    case thread_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING " handle_thread Thread (default): Operation: ~p, Args: ~p", [ Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_thread(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_thread returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, Answer);

                false -> % error is handled by the operation
                    ok;

                true ->
                    Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                    send_element(State, (Answer));

                {ok, []} ->
                    Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
                    send_element(State, (Answer));

                {ok, true} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"true">>}
                    ]),
                    send_element(State, (Answer));

                {ok, false} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"false">>}
                    ]),
                    send_element(State, (Answer));
                    
                {ok, Result} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_thread error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));


                Result ->
                    ?ERROR_MSG(?MODULE_STRING " handle_thread returns: ~p", [Result]),
                    Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                    send_element(State, (Answer))
             end
    end.

thread_operations(<<"list">>) -> ?THREAD_LIST;
thread_operations(<<"tree">>) -> ?THREAD_TREE;
thread_operations(<<"search">>) -> ?THREAD_SEARCH;
thread_operations(<<"bounds">>) -> ?THREAD_BOUNDS;
thread_operations(<<"subscribe">>) -> ?THREAD_SUBSCRIBE;
thread_operations(<<"getmessage">>) -> ?THREAD_GETMESSAGE;
thread_operations(<<"subscribers">>) -> ?THREAD_SUBSCRIBERS;
thread_operations(<<"unsubscribe">>) -> ?THREAD_UNSUBSCRIBE;
thread_operations(_) -> false.

do_thread(Op, User, _SeqId, _Args, State) when 
    Op =:= ?THREAD_LIST ->
    
    thread(State, Op, User, undefined);

do_thread(Op, User, SeqId, Args, State) when 
    Op =:= ?THREAD_BOUNDS;
    Op =:= ?THREAD_SUBSCRIBERS ->
    case args(Args, [<<"id">>]) of
        [ _Id ] = Params ->
            thread(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: id">>),
            send_element(State, (Answer)),
            false
    end;

do_thread(Op, User, SeqId, Args, State) when 
    Op =:= ?THREAD_SUBSCRIBE;
    Op =:= ?THREAD_UNSUBSCRIBE ->
    case args(Args, [<<"id">>]) of
        [ _Id ] = Params ->
            thread(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: id">>),
            send_element(State, (Answer)),
            false
    end;

do_thread(Op, User, SeqId, Args, State) when 
    Op =:= ?THREAD_GETMESSAGE ->
    case args(Args, [<<"id">>, <<"msgid">>]) of
        [ _Id, _Msgid ] = Params ->
            thread(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_thread(_Operation, _User, _SeqId, _Args, _State) ->
    ok.

handle_contactlist(Operation, SeqId, Args, State) ->
    case contactlist_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING " handle_contactlist ContactList (default): Operation: ~p, Args: ~p", [ Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_contactlist(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_contactlist returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, Answer);

                false -> % error is handled by the operation
                    ok;

                true ->
                    Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                    send_element(State, (Answer));

                {ok, []} ->
                    Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
                    send_element(State, (Answer));

                {ok, true} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"true">>}
                    ]),
                    send_element(State, (Answer));

                {ok, false} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"false">>}
                    ]),
                    send_element(State, (Answer));
                    
                {ok, Result} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_contactlist error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                Result ->
                    ?ERROR_MSG(?MODULE_STRING " handle_contactlist returns: ~p", [Result]),
                    Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                    send_element(State, (Answer))
            end
    end.

contactlist_operations(<<"list">>) -> ?THREAD_LIST;
contactlist_operations(_) -> false.

do_contactlist(Op, User, _SeqId, _Args, State) when 
    Op =:= ?THREAD_LIST ->

    contactlist(State, Op, User, undefined);

do_contactlist(Op, User, SeqId, Args, State) when 
    Op =:= ?THREAD_BOUNDS;
    Op =:= ?THREAD_SUBSCRIBERS ->

    case args(Args, [<<"id">>]) of
        [ _Id ] = Params ->
            contactlist(State, Op, User, Params);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: id">>),
            send_element(State, (Answer)),
            false
    end;

do_contactlist(_Operation, _User, _SeqId, _Args, _State) ->
    ?ERROR_MSG("DEFAULT(~p): do_contactlist ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

contactlist(#state{userid= Userid} = State, ?THREAD_LIST, _User, _) ->
    data_specific(State, hyd_users, contactlists, [ Userid ]);

contactlist(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): contactlist ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, Userid, Operation, User, Args ]),
    {error, enoent}.

%%
%% handle_state 
handle_state(Operation, SeqId, Args, #state{ server=Host, userid=Creator } = State) ->
    case args(Args, [<<"to">>]) of
        [ Element ] ->
            RoomType = 1,
            mod_chat:create_room(Host, RoomType, Creator, Element, []), % this will create synchronously the room if needed

            OperationArgs = case args(Args, [<<"args">>]) of % extract args to transfert directly
                [] ->
                    [];
                [ _Elements ] ->
                    _Elements
            end,
            Packet = make_packet( State, <<"state">>, [
                { <<"user">>, Creator},
                { <<"operation">>, Operation},
                { <<"args">>, OperationArgs}]),
            mod_chat:route(Host, Element, Creator, message, Packet);
        
        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: to">>),
            send_element(State, (Answer)),
            false
    end.

% Handling <<"pages">>
handle_page(Operation, SeqId, Args, State) ->
    case page_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING " handle_page Page (default): Operation: ~p, Args: ~p", [ Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_page(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_page returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, Answer);

                false -> % error is handled by the operation
                    ok;

                true ->
                    Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                    send_element(State, Answer);

                {ok, []} ->
                    Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
                    send_element(State, Answer);
                    
                {ok, true} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"true">>}
                    ]),
                    send_element(State, (Answer));

                {ok, false} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, <<"false">>}
                    ]),
                    send_element(State, (Answer));
                    
                {ok, Result} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_page error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                Result ->
                    ?ERROR_MSG(?MODULE_STRING " handle_page returns: ~p", [Result]),
                    Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                    send_element(State, (Answer))
            end
    end.

page_operations(<<"list">>) -> ?THREAD_LIST;
page_operations(<<"explore">>) -> ?GENERIC_EXPLORE;
page_operations(_) -> false.

do_page(Op, User, _SeqId, _Args, State) when 
    Op =:= ?THREAD_LIST ->

    page(State, Op, User, undefined);

do_page(Op, User, _SeqId, Args, State) when 
    Op =:= ?GENERIC_EXPLORE ->

    Params = args(Args, [<<"count">>, <<"way">>, <<"from">>]),
    page(State, Op, User, Params);

do_page(_Operation, _User, _SeqId, _Args, _State) ->
    ?DEBUG("DEFAULT(~p): do_page ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

page(#state{userid=Userid} = State, ?THREAD_LIST, _User, _) ->
    data_specific(State, hyd_users, pages, [ Userid ]);

page(#state{userid=Userid} = State, ?GENERIC_EXPLORE, _User, Args) ->
    data_specific(State, hyd_pages, explore, [ Userid | Args ]);

page(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): page ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, Userid, Operation, User, Args ]),
    {error, enoent}.

% subscriptions
subscription_operations(<<"list">>) -> ?THREAD_LIST;
subscription_operations(_) -> false.

do_subscription(Op, User, _SeqId, _Args, State) when 
    Op =:= ?THREAD_LIST ->

    subscription(State, Op, User, undefined);

do_subscription(_Operation, _User, _SeqId, _Args, _State) ->
    ?DEBUG("DEFAULT(~p): do_subscription ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

subscription(#state{userid=Userid} = State, ?THREAD_LIST, _User, _) ->
    data_specific(State, hyd_users, subscriptions, [ Userid ]);

subscription(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): subscription ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, Userid, Operation, User, Args ]),
    {error, enoent}.

% comgroups
comgroups() -> <<"comgroups">>.

comgroup_operations(<<"list">>) -> ?THREAD_LIST;
comgroup_operations(<<"explore">>) -> ?GENERIC_EXPLORE;
comgroup_operations(_) -> false.

do_comgroup(Op, User, _SeqId, _Args, State) when 
    Op =:= ?THREAD_LIST ->

    comgroup(State, Op, User, undefined);

do_comgroup(Op, User, _SeqId, Args, State) when 
    Op =:= ?GENERIC_EXPLORE ->

    Params = args(Args, [<<"count">>, <<"way">>, <<"from">>]),
    comgroup(State, Op, User, Params);

do_comgroup(_Operation, _User, _SeqId, _Args, _State) ->
    ?DEBUG("DEFAULT(~p): do_comgroup ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

comgroup(#state{userid=Userid} = State, ?THREAD_LIST, _User, _) ->
    data_specific(State, hyd_users, comgroups, [ Userid ]);

comgroup(#state{userid=Userid} = State, ?GENERIC_EXPLORE, _User, Args) ->
    data_specific(State, hyd, explore, [ comgroups(),  Userid | Args ]);

comgroup(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): ~p ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, comgroups(), Userid, Operation, User, Args ]),
    {error, enoent}.


% admin

admin_operations(<<"set">>) -> ?OPERATION_SETINFO;
admin_operations(<<"info">>) -> ?OPERATION_ABOUT;
admin_operations(<<"user">>) -> ?OPERATION_STOREPROFILE;
admin_operations(_) -> false.

do_admin(?OPERATION_SETINFO = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"id">>, <<"section">>, <<"values">>]) of
        [ Userid, Section, {struct, Values} ] ->
            admin(State, Op, User, [ Userid, Section, Values ]);

        _Wrong ->
            ?ERROR_MSG(?MODULE_STRING ".~p do_admin: extracted: ~p", [ ?LINE, _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_admin(?OPERATION_ABOUT = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"id">>, <<"section">>]) of
        [ Id, Section ] ->
            admin(State, Op, User, [ Id, Section ]);

        _Wrong ->
            ?ERROR_MSG(?MODULE_STRING ".~p do_admin: extracted: ~p", [ ?LINE, _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;

do_admin(?OPERATION_STOREPROFILE = Op, User, SeqId, Args, State) ->
    case args(Args, [<<"id">>, <<"values">>]) of
        [ Id, {struct, Values} ] ->
            case args(Values, [<<"firstname">>, <<"lastname">>, <<"domain">>]) of
                [ Firstname, Lastname, Domain ] ->
                    admin(State, Op, User, [ Id, Firstname, Lastname, Domain ]);

                _ ->
                    Answer = make_error(SeqId, 406, <<"missing arguments">>),
                    send_element(State, (Answer)),
                    false
            end;

        _Wrong ->
            ?ERROR_MSG(?MODULE_STRING ".~p do_admin: extracted: ~p", [ ?LINE, _Wrong ]),
            Answer = make_error(SeqId, 406, <<"bad arguments">>),
            send_element(State, (Answer)),
            false
    end;


do_admin(_Operation, _User, _SeqId, _Args, _State) ->
    ?DEBUG(?MODULE_STRING "[~5w] DEFAULT: do_admin ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

admin(#state{userid=Userid} = State, ?OPERATION_SETINFO, _User, Args) ->
    data_specific(State, hyd_admin, set_value, [ Userid | Args ]);

admin(#state{userid=Userid} = State, ?OPERATION_ABOUT, _User, Args) ->
    data_specific(State, hyd_admin, get_value, [ Userid | Args ]);

admin(#state{userid=Userid} = State, ?OPERATION_STOREPROFILE, _User, Args) ->
    data_specific(State, hyd_admin, create_user, [ Userid | Args ]);

admin(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG(?MODULE_STRING "[~5w] DEFAULT: admin ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, Userid, Operation, User, Args ]),
    {error, enoent}.


%%
%% Handle_action 
%%    1) Retrieve argument of this action
%%    2) Call this action
%%    3) returns the result
%% returns new state
handle_action(Operation, SeqId, Args, State) ->
    case args(Args, [<<"to">>]) of
        [ Element ] ->
            ?DEBUG(?MODULE_STRING "[~5w] handle_Action: operation: ~p, on Element: ~p", [ ?LINE, Operation, Element] ),
            case get_args(State, Element, Operation) of
                {error, Reason} ->
                    ?ERROR_MSG(?MODULE_STRING " handle_action error: ~p", [ Reason ]),
                    Answer = make_error(Reason, SeqId, 404, <<"invalid action">>),
                    send_element(State, Answer),
                    State;

                {ok, []} -> % no extra args
                    ?DEBUG(?MODULE_STRING "[~5w] handle_action no ActionArgs", [ ?LINE ]),
                    hyd_fqids:action_async(SeqId, Element, Operation, [ State#state.userid ]),
                    Actions = State#state.aux_fields,
                    State#state{aux_fields=[{SeqId, [ Element, Operation, [] ]} | Actions ]};

%%                     case data(State, hyd_fqids, action, [ Element, Operation, [ State#state.userid ]]) of
%%                         {error, Reason} ->
%%                             Answer = make_error(Reason, SeqId, 500, <<"error action">>),
%%                             send_element(State, Answer),
%%                             State;
%% 
%%                         {ok, []} ->
%%                             Answer = make_answer_not_found(SeqId),
%%                             send_element(State, Answer),
%%                             State;
%% 
%%                         {ok, true} ->
%%                             Answer = make_answer(SeqId, 200, [
%%                                 {<<"result">>, <<"true">>}
%%                             ]),
%%                             send_element(State, Answer),
%%                             State;
%% 
%%                         {ok, false} ->
%%                             Answer = make_answer(SeqId, 200, [
%%                                 {<<"result">>, <<"false">>}
%%                             ]),
%%                             send_element(State, Answer),
%%                             State;
%% 
%%                         {ok, {Infos, Response}} ->
%%                             Answer = make_result(SeqId, Response),
%%                             send_element(State, Answer),
%%                             action_trigger(State, Element, Infos, Operation, [], Response),
%%                             State;
%% 
%%                         % DEPRECATED
%%                         {ok, Response} ->
%%                             Answer = make_result(SeqId, Response),
%%                             send_element(State, Answer),
%%                             State
%%                    end;

                {ok, ActionArgs} ->
                    Params = action_args(Args, ActionArgs),
                    case check_args(ActionArgs, Params) of
                        true ->
                            ?DEBUG(?MODULE_STRING "[~5w] handle_action ActionArgs: ~p, Args: ~p, -> Params: ~p", [ ?LINE, ActionArgs, Args, Params ]),
                            hyd_fqids:action_async(SeqId, Element, Operation, [ State#state.userid | Params ]),
                            Actions = State#state.aux_fields,
                            State#state{aux_fields=[{SeqId, [ Element, Operation, Params ]} | Actions ]};

                        false ->
                            Answer = make_error(SeqId, 406, <<"invalid arguments provided">>),
                            send_element(State, Answer),
                            State
                    end
            end;
                
        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: to">>),
            send_element(State, Answer),
            State
    end.

handle_search(Operation, SeqId, Args, State) ->
    case search_operations(Operation) of
        false ->
            ?ERROR_MSG(?MODULE_STRING " handle_search Search (default): Operation: ~p, Args: ~p", [ Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call">>),
            send_element(State, (Answer));

        OperationId ->
            #jid{luser=User, lserver=_Host} = State#state.jid,
            case do_search(OperationId, User, SeqId, Args, State) of
                [] ->
                    ?DEBUG(?MODULE_STRING " handle_search returns empty", []),
                    Answer = make_answer_not_found(SeqId),
                    send_element(State, (Answer));

                false -> % error is handled by the operation
                    ok;

                true ->
                    Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
                    send_element(State, (Answer));

                {ok, []} ->
                    Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
                    send_element(State, (Answer));
                    
                {ok, Result} ->
                    Answer = make_answer(SeqId, 200, [
                        {<<"result">>, Result}
                    ]),
                    send_element(State, (Answer));

                {error, Reason} -> 
                    ?ERROR_MSG(?MODULE_STRING "[~5w] handle_search error: ~p", [ ?LINE, Reason ]),
                    Answer = make_error(Reason, SeqId, 500, <<"internal server error">>),
                    send_element(State, (Answer));

                Result ->
                    ?ERROR_MSG(?MODULE_STRING " handle_search returns: ~p", [Result]),
                    Answer = make_answer(SeqId, [{<<"result">>, Result}]),
                    send_element(State, (Answer))
	    end
    end.

search_operations(<<"new">>) -> ?OPERATION_SEARCH_NEW;
search_operations(<<"query">>) -> ?OPERATION_SEARCH_QUERY;
search_operations(_) -> false.

do_search(Op, User, SeqId, Args, State) when 
    Op =:= ?OPERATION_SEARCH_NEW ->

    case args(Args, [<<"title">>, <<"queries">>]) of
        [Title, {struct, Queries}] ->
            search(State, Op, User, [Title, Queries]);

        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: queries">>),
            send_element(State, (Answer)),
            false
    end;

do_search(Op, User, SeqId, Args, State) when 
    Op =:= ?OPERATION_SEARCH_QUERY ->

    case args(Args, [<<"id">>, <<"set">>, <<"limit">>, <<"order">> ]) of
        [ _Id, _Type, _Limit, _Order ] = Params ->
            search(State, Op, User, Params);

        [ _Id, _Type, _Limit ] = Params ->
            search(State, Op, User, Params);

        [ _Id, _Type ] = Params ->
            search(State, Op, User, Params);

        _ ->
            case args(Args, [<<"id">>, <<"set">>, <<"order">> ]) of
                [ _Id, _Type, _Order ] ->
                    search(State, Op, User, [ _Id, _Type, [], _Order]);

                _ ->
                    Answer = make_error(SeqId, 406, <<"missing arguments, id or set or limit or order">>),
                    send_element(State, (Answer)),
                    false
            end
    end;

do_search(_Operation, _User, _SeqId, _Args, _State) ->
    ?DEBUG("DEFAULT(~p): do_search ~p: Operation: ~p, on User: ~p, Seq: ~p, Args: ~p", [ ?LINE, _User, _Operation, _SeqId, _Args ]),
    ok.

search(#state{userid=Userid} = State, ?OPERATION_SEARCH_NEW, _User, Params) ->
    data_specific(State, hyd_queries, new, [ Userid, Params ]);

search(#state{userid=Userid} = State, ?OPERATION_SEARCH_QUERY, _User, Params) ->
    data_specific(State, hyd_queries, 'query', [ Userid, Params ]);

search(#state{userid=Userid} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): Group ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, Userid, Operation, User, Args ]),
    {error, enoent}.

%internal get_args
get_args(_, Element, Operation) when
    Element =:= <<>> ;
    Operation =:= <<>> ->
    {error, badarg};
get_args(State, Element, Operation) ->
    operation_args(State, [ Element, Operation, State#state.userid ]).

-spec operation_args(
    State :: #state{},
    Args :: list() ) -> {ok, list()} | {error, term()}.

operation_args(State, Args) ->
    ?DEBUG(?MODULE_STRING "[~5w] operation_args: Args: ~p", [ ?LINE, Args ]),
    %Result = rpc:call(Db, hyd_fqids, args, Args), % synchro call
    %[ Fqid, Function | _ ] = Args,
    Result = apply(hyd_fqids, args, Args),
    %?DEBUG(?MODULE_STRING " [~s (~p|~p)] operation_args: Result: ~p", [ Username, seqid(), _Sid, Result ]),
    case Result of 
        {badrpc, Reason} ->
            {error, Reason};

        [<<>>] ->
            {error, invalid};

        {error, {_Operation, {timeout, _}} = Error} -> % will retry
            ?ERROR_MSG(?MODULE_STRING "[~5w] operations_args: retry because error: ~p, args: ~p", [ ?LINE, Error, Args ]),
            operation_args(State, Args);

        {error, _ } = Error ->
            ?ERROR_MSG(?MODULE_STRING "[~5w] operations_args: error: ~p, args: ~p", [ ?LINE, Error, Args ]),
            Error;

        [] ->
            {ok, []}; % empty response because nothing was found or done

        Response ->  % there is many response or a complex response
            {ok, Response}

    end.

% SERVER to USER
% this message is sent from the server to the user
handle_message({game, [ QId, Title, Choices ]}, From, _To, State) ->
    Answers = binary:split( Choices, <<"~">>, [global]),
    #jid{lresource=GameRef} = From,
    Data = [{<<"action">>, [
                {<<"type">>,<<"quizz">>},
                {<<"operation">>,<<"question">>},
                {<<"from">>, GameRef}, 
                {<<"to">>, [
                    {<<"id">>, jlib:jid_to_string(State#state.jid)},
                    {<<"userid">>, State#state.userid},
                    {<<"nick">>, State#state.user}
                ]},
                {<<"question">>, [
                    {<<"label">>,Title},
                    {<<"answers">>, Answers},
                    {<<"id">>, list_to_binary(QId)},
                    {<<"timeout">>,10000}
                ]}
            ]}],
    Packet = (Data),
    {ok, Packet};

handle_message({game, {score, Score}}, From, _To, State) ->
    #jid{lresource=GameRef} = From,
    Data = [{<<"action">>, [
                {<<"type">>,<<"quizz">>},
                {<<"operation">>,<<"score">>},
                {<<"from">>, GameRef}, 
                {<<"to">>, [
                    {<<"id">>, jlib:jid_to_string(State#state.jid)},
                     {<<"userid">>, State#state.userid},
                     {<<"nick">>, State#state.user}
                ]},
                {<<"score">>, lists:map(fun({Player, Win, Loss}) ->
                    [
                        {<<"id">>, Player},
                        {<<"win">>, lists:map( fun list_to_integer/1, Win )},
                        {<<"loss">>, lists:map( fun list_to_integer/1, Loss )}
                    ] end, Score)} 
                ]
            }],
    Packet = (Data),
    {ok, Packet};

handle_message({game, eof}, From, _To, State) ->
    #jid{lresource=GameRef} = From,
    Data = [{<<"action">>, [
                {<<"type">>,<<"quizz">>},
                {<<"operation">>,<<"end">>},
                {<<"from">>, GameRef}, 
                to(State)
            ]}],
    Packet = (Data),
    {ok, Packet};
    
handle_message({chat, {Msgid, Message}}, _From, _To, State) ->
    Data = [{<<"message">>, [
                {<<"type">>,<<"chat">>},
                %{<<"from">>, Ref}, 
                to(State),
                {<<"msgid">>, Msgid },
                {<<"data">>, Message}
            ]}],
    Packet = (Data),
    {ok, Packet};

handle_message({notification, {Msgid, Message}}, _From, _To, State) ->
    Data = [{<<"message">>, [
                {<<"type">>,<<"notification">>},
                to(State),
                {<<"msgid">>, Msgid },
                {<<"data">>, Message}
            ]}],
    Packet = (Data),
    {ok, Packet};

% the message Child must be deleted
handle_message({event, {Msgid, {delete, Child}}}, From, _To, State) ->
    #jid{lresource=Ref} = From,
    Data = [{<<"message">>, [
                {<<"type">>,<<"action">>},
                {<<"from">>, Ref}, 
                to(State),
                {<<"msgid">>, Msgid },
                {<<"data">>, [
                    {<<"operation">>,<<"delete">>},
                    {<<"child">>, Child}]}
            ]}],
    Packet = (Data),
    {ok, Packet};

handle_message({event, {Msgid, Message}}, From, _To, State) ->
    #jid{lresource=Ref} = From,
    Data = [{<<"message">>, [
                {<<"type">>,<<"event">>},
                {<<"from">>, Ref}, 
                to(State),
                {<<"msgid">>, Msgid },
                {<<"event">>, Message}
            ]}],
    Packet = (Data),
    {ok, Packet};

% synchronization: notifying client the need for synchronization
handle_message({sync, Property}, _From, _To, _State) ->
    Data = [{<<"message">>, [
                {<<"type">>,<<"sync">>},
                {<<"property">>, Property} ]
            }],
    Packet = (Data),
    {ok, Packet};

handle_message({plain, Message}, _From, _To, _) ->
    ?DEBUG(?MODULE_STRING " handle_message plain packet: From: ~p, To: ~p", [ _From, _To ]),
    {ok, Message};

handle_message({binary, Message}, _From, _To, _) ->
    ?DEBUG(?MODULE_STRING " handle_message *binary* data: From: ~p, To: ~p, ~p bytes", [ _From, _To, iolist_size(Message) ]),
    {ok, Message};

handle_message(Message, _From, _To, _) ->
    ?DEBUG(?MODULE_STRING " handle_message default: From: ~p, To: ~p\n~p", [ _From, _To, Message ]),
    {ok, Message}.

userid(State, User, Server, Password) ->
    case data_specific(State, hyd_users, userid, [User,Server,Password]) of
        [] ->
            {error, invalid};

        {ok, []} ->
            {error, invalid};

        {ok, [{_, UserId}]} ->
            {ok, UserId}
    end.

-spec data_specific(
    State :: #state{},
    Module :: atom(),
    Function :: atom(),
    Args :: list() ) -> [] | list() | {error, term()}.

data_specific(#state{db=Db, sid=_Sid, user=Username, server=_Server}, Module, Function, Args) ->
    ?DEBUG(?MODULE_STRING "[~5w] [~s (~p|~p)] data_specific: Db: ~p  apply(~p, ~p, ~p)", [ 
        ?LINE,
        Username, seqid(), _Sid,
        Db, Module, Function, Args ]),

    Result = apply(Module, Function, Args), % slowest call possible :)
    case Result of 
        {badrpc, Reason} ->
            {error, Reason};

        <<>> ->
            {error, invalid};

        [] ->
            [];

        % sucess or failure
        [Bool] when Bool =:= true; Bool =:= false ->
            {ok, Bool};

        {ok, ["0"]} -> % success
            <<"ok">>;

        {error, undefined} ->
            [];

        {error, _Any } = Error -> % call error
            ?ERROR_MSG(?MODULE_STRING " [~s (~p|~p)] data_specific: call error: ~p", [ Username, seqid(), _Sid, Error ]),
            Error;

        [ {error, _} = Error | _ ] -> % backend app error
            ?ERROR_MSG(?MODULE_STRING " [~s (~p|~p)] data_specific: backend error: ~p", [ Username, seqid(), _Sid, Error ]),
            Error;

        {ok, Bool} when Bool =:= true ; Bool =:= false ->
            {ok, Bool};

        {ok, _} = Response -> %% FIXME is this case needed ?
            ?DEBUG(?MODULE_STRING " [~s (~p|~p)] data_specific: backend response: ~p", [ Username, seqid(), _Sid, Response ]),
            Response;

        Any -> %% Error are assumed to be catched earlier
            ?DEBUG(?MODULE_STRING "[~5w] [~s (~p|~p)] data_specific: backend catchall: ~p", [ ?LINE, Username, seqid(), _Sid, Any ]),
            {ok, Any}
    end.

data(#state{sid=_Sid, user=Username, server=_Server}, Module, Function, Args) ->
    ?DEBUG(?MODULE_STRING " [~s (~p|~p)] DATA: Module: ~p, Function: ~p, Args: ~p", [ 
        Username, seqid(), _Sid, 
        Module, Function, Args ]),
    %Result = rpc:call(Db, Module, Function, Args), % synchro call
    Result = apply(Module, Function, Args), 
    %?DEBUG(?MODULE_STRING " [~s (~p|~p)] DATA: Result: ~p", [ Username, seqid(), _Sid, Result ]),
    case Result of 
        {badrpc, Reason} ->
            {error, Reason};

        [<<>>] ->
            {error, invalid};

        {error, _ } = Error ->
            ?DEBUG(?MODULE_STRING " [~s (~p|~p) ] data: call error: ~p, call: ~p:~p ~p", [ Username, seqid(), _Sid, Error, Module, Function, Args ]),
            Error;

        [ {error, _} = Error | _ ] -> % backend app error
            ?ERROR_MSG(?MODULE_STRING " [~s (~p|~p)] data: backend error: ~p, call: ~p:~p ~p", [ Username, seqid(), _Sid, Error, Module, Function, Args ]),
            Error;

        [true] ->
            {ok, []};

        [] ->
            {ok, []}; % empty response because nothing was found or done

        [ Response ] -> % there is only one response
            {ok, Response};

        Response ->  % there is many response or a complex response
            {ok, Response}

    end.


% Helpers
profile(State, ?OPERATION_GETALLINTERNALDATA, _User) ->
    data_specific(State, hyd_users, info, [ State#state.userid ]);

profile(State, ?OPERATION_GETCONTACTLIST, _User) ->
    data_specific(State, hyd_users, contacts, [ State#state.userid ]);

profile(State, ?OPERATION_GETLABELS, Params) ->
    data_specific(State, hyd_users, infotree_get_field, Params);

profile(State, ?OPERATION_GETCONTACTTREE, _User) ->
    data_specific(State, hyd_users, contacts_tree, [ State#state.userid ]);

profile(State, ?OPERATION_GETOTHERCONTACTTREE, Params) ->
    data_specific(State, hyd_users, contacts_tree, Params);

profile(#state{userid=Userid} = State, ?OPERATION_GETCONTACTINFO, Params) ->
    data_specific(State, hyd_users, info_user, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_ABOUT, Params) ->
    data_specific(State, hyd_users, info_about, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETINFO, Params) ->
    data_specific(State, hyd_users, infotree_set_value, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETINFO_TMP, Params) ->
    data_specific(State, hyd_users, infotree_set_value_tmp, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_VALIDATE, Params) ->
    data_specific(State, hyd_users, infotree_validate, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_CONTRACT, Params) ->
    data_specific(State, hyd_users, infotree_contract, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_CANCEL, Params) ->
    data_specific(State, hyd_users, infotree_cancel, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_DELETEINFO, Params) ->
    data_specific(State, hyd_users, delete_info, [ Userid, Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETLABEL, Params) ->
    data_specific(State, hyd_users, infotree_set_label, [ Userid | Params ]);

profile(State, ?OPERATION_GETCONFIGURATION, _User) ->
    data_specific(State, hyd_users, config_all, [ State#state.userid ]);

profile(State, ?OPERATION_GETCONFIGURATION_VALUE,  Id) ->
    data_specific(State, hyd_users, config_get_value, [ State#state.userid, Id ]);

profile(State, ?OPERATION_RESETCONFIGURATION_VALUE,  Id) ->
    data_specific(State, hyd_users, config_restore_value, [ State#state.userid, Id ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETCONFIGURATION_VALUE, [ Id, Args ]) ->
    data_specific(State, hyd_users, config_set_value, [ Userid, Id, Args ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETREGISTRY_VALUE, [ Id, Args ]) ->
    data_specific(State, hyd_users, registry_set_value, [ Userid, Id, Args ]);

profile(State, ?OPERATION_GETVISIBILITY_VALUE,  Id) ->
    data_specific(State, hyd_users, visibility_get_value, [ State#state.userid, Id ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETVISIBILITY_VALUE, [ Id, Args ]) ->
    data_specific(State, hyd_users, visibility_set_value, [ Userid, Id, Args ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETVISIBILITY, Params) ->
    data_specific(State, hyd_users, infotree_set_visibility, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_SETVISIBILITY_TMP, Params) ->
    data_specific(State, hyd_users, infotree_set_visibility_tmp, [ Userid | Params ]);

profile(#state{userid=Userid} = State, ?OPERATION_GETPROFILETREE, _User) ->
    data_specific(State, hyd_users, profiles_tree, [ Userid ]);

profile(State, ?OPERATION_GETPROFILELIST, _User) ->
    data_specific(State, hyd_users, profiles, [ State#state.userid ]);

profile(State, ?OPERATION_GETSCHEDULE, _User) ->
    data_specific(State, hyd_users, contacts_tree, [ State#state.userid ]);

profile(State, ?OPERATION_GETPROPERTIES, Type) ->
    data_specific(State, hyd_users, info, [ State#state.userid, Type ]);

profile(State, ?OPERATION_GETCATEGORIES, _) ->
    data_specific(State, hyd_users, contacts_categories, [ State#state.userid ]);

% STORE -> is using the registree
profile(State, ?OPERATION_STOREPROFILE, [ ProfileName, Values ]) ->
    data_specific(State, hyd_users, registry_set_value, [ State#state.userid, ProfileName, Values ]);

profile(State, ?OPERATION_STOREPROFILE, [ ProfileName, Category, Value ]) ->
    data_specific(State, hyd_users, registry_set_value, [ State#state.userid, ProfileName, Category, Value ]);

profile(State, ?OPERATION_SETPROFILE, [ ProfileName, Category, Value ]) ->
    data_specific(State, hyd_users, profile_set_value, [ State#state.userid, ProfileName, Category, Value ]);

profile(State, ?OPERATION_DELPROFILECATEGORY, [ ProfileName, Category ]) ->
    data_specific(State, hyd_users, profile_del_value, [ State#state.userid, ProfileName, Category ]);

profile(State, ?OPERATION_SETPROFILEPRESENCE, [ ProfileName, Category, Value ]) ->
    data_specific(State, hyd_users, presence_set, [ State#state.userid, ProfileName, Category, Value ]);

% FIXME profile -> profile_get
profile(State, ?OPERATION_GETPROFILE, [ ProfileName ]) ->
    data_specific(State, hyd_users, profile, [ State#state.userid, ProfileName ]);

profile(State, ?OPERATION_RESTOREPROFILE, Args) ->
    data_specific(State, hyd_users, profile_restore, [ State#state.userid | Args ]);

profile(State, ?OPERATION_DELETEPROFILE, Args) ->
    data_specific(State, hyd_users, profile_delete, [ State#state.userid | Args ]);
	
profile(#state{userid=Userid} = _State, Operation, Args ) ->
    ?DEBUG("DEFAULT(~p): Profile ~p: Operation: ~p, Args: ~p", [ ?LINE, Userid, Operation, Args ]),
    {error, enoent}.



% Contacts helpers
contacts(#state{userid=_UserId} = State, ?OPERATION_GETUSERINFOS, _, [ ContactId ]) ->
    data_specific(State, hyd_users, info, [ ContactId, <<"visible">> ]);
    %data_specific(State, hyd_users, info_user, [ UserId, ContactId ]);

contacts(#state{userid=UserId} = State, ?OPERATION_ISFAVORITE, _, [ ContactId ]) ->
    data_specific(State, hyd_users, infotree_get_own_value, [ UserId, ContactId, <<"General">>, <<"favorite">> ]);

contacts(#state{userid=Userid} = State, ?OPERATION_LISTBLOCKED, _, []) ->
    data_specific(State, hyd_users, list_blocked, [ Userid ]);

contacts(#state{userid=Userid} = State, ?OPERATION_LISTBLOCKED, _, Args) ->
    data_specific(State, hyd_users, list_blocked, [ Userid | Args ]);

contacts(#state{userid=Userid} = State, ?OPERATION_GETCATEGORIES, _, _) ->
    data_specific(State, hyd_users, contacts_categories, [ Userid ]);

contacts(#state{userid=Userid} = State, ?OPERATION_GETCONTACTSFROMCATEGORY, _, Params) ->
    data_specific(State, hyd_users, contacts_info_from_category, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_GETINVITATIONS, _, Params) ->
    data_specific(State, hyd_users, contacts_info_from_invitations, [ Userid | Params ]);

contacts(State, ?OPERATION_GETLABELS, _, Params) ->
    data_specific(State, hyd_users, infotree_get_field, Params);

contacts(#state{userid=Userid} = State, ?OPERATION_GETCONTACTTREE, _, _) ->
    data_specific(State, hyd_users, contacts_tree, [ Userid ]);

contacts(#state{userid=UserId} = State, ?OPERATION_GETCONTACTLIST, _, [ Category ]) ->
    data_specific(State, hyd_users, all_contacts_from_category, [ UserId, Category ]);

contacts(#state{userid=UserId} = State, ?OPERATION_GETCONTACTLIST, _, []) ->
    data_specific(State, hyd_users, contacts, [ UserId ]);

contacts(#state{userid=UserId} = State, ?OPERATION_ADDCONTACT, _User, [ ContactId ]) ->
    data_specific(State, hyd_users, add_contact, [ UserId, ContactId ]);

contacts(#state{userid=UserId} = State, ?OPERATION_INVITECONTACT, _User, Params) ->
    data_specific(State, hyd_users, invite_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_ACCEPTCONTACT, _User, Params) ->
    data_specific(State, hyd_users, accept_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_REFUSEINVITATION, _User, Params) ->
    data_specific(State, hyd_users, refuse_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_CANCELINVITATION, _User, Params) ->
    data_specific(State, hyd_users, cancel_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_UNBLOCKCONTACT, _User, Params) ->
    data_specific(State, hyd_users, unblock_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_BLOCKCONTACT, _User, Params) ->
    data_specific(State, hyd_users, block_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_DELETECONTACT, _User, Params) ->
    data_specific(State, hyd_users, delete_contact, [ UserId | Params ]);

contacts(#state{userid=UserId} = State, ?OPERATION_DELETECONTACTINFO, _User, [ Contactid | Rest ] ) ->
    data_specific(State, hyd_users, delete_own_info, [ UserId, Contactid, Rest ]);

contacts(#state{userid=UserId} = State, ?OPERATION_ADDCONTACTINCATEGORY, _User, [ ContactId, Category ]) ->
    data_specific(State, hyd_users, add_contact_in_category, [ UserId, ContactId, Category ]);

contacts(#state{userid=Userid} = State, ?OPERATION_GETCONTACTINFO, _User, Params) ->
    data_specific(State, hyd_users, info_contact, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_GETCONTACTINFOBIS, _User, Params) ->
    data_specific(State, hyd_users, info_own_contact, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_SETINFO, _, Params) ->
    data_specific(State, hyd_users, infotree_set_own_value, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_SETINFO_TMP, _, Params) ->
    data_specific(State, hyd_users, infotree_set_own_value_tmp, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_SETLABEL, _, Params) ->
    data_specific(State, hyd_users, infotree_set_own_label, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_VALIDATE, _, Params) ->
    data_specific(State, hyd_users, infotree_validate, [ Userid | Params ]);

contacts(#state{userid=Userid} = State, ?OPERATION_CANCEL, _, Params) ->
    data_specific(State, hyd_users, infotree_cancel, [ Userid | Params ]);

contacts(#state{userid=UserId} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): Contacts ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, UserId, Operation, User, Args ]),
    {error, enoent}.

% Thread helpers
thread(#state{userid= Userid} = State, ?THREAD_LIST, _User, _) ->
    data_specific(State, hyd_users, threads, [ Userid ]);

thread(#state{userid= _UserId} = State, ?THREAD_BOUNDS, _User, [ Id ]) ->
    data_specific(State, hyd_threads, bounds, [ Id ]);

thread(#state{userid= _UserId} = State, ?THREAD_SUBSCRIBERS, _User, [ Id ]) ->
    data_specific(State, hyd_threads, subscribers, [ Id ]);

thread(#state{userid = Userid} = State, ?THREAD_SUBSCRIBE, _User, [ Id ]) ->
    data_specific(State, hyd_threads, subscribe, [ Id, Userid ]);

thread(#state{userid = Userid} = State, ?THREAD_UNSUBSCRIBE, _User, [ Id ]) ->
    data_specific(State, hyd_threads, unsubscribe, [ Id, Userid ]);

thread(#state{userid= _UserId} = State, ?THREAD_GETMESSAGE, _User, [ Threadid, Msgid ]) ->
    data_specific(State, hyd_messages, get, [ Threadid, Msgid ]);

thread(#state{userid=UserId} = _State, Operation, User, Args) ->
    ?DEBUG("DEFAULT(~p): Thread ~p: Operation: ~p, on User: ~p, Args: ~p", [ ?LINE, UserId, Operation, User, Args ]),
    {error, enoent}.

-spec args(
    Args::list(),
    Keys::list() ) -> list().

args(Args, Keys) ->
    args(Args, Keys, []).
args(_, [], Result) ->
    lists:reverse(Result);
args(Args, [ Key | Keys ], Result) ->
    case fxml:get_attr_s(Key, Args) of
        <<>> ->
            args(Args, Keys, Result);
        Value ->
            args(Args, Keys, [Value|Result])
    end.

action_args(Args, Keys) ->
    action_args(Args, Keys, []).
action_args(_, [], Result) ->
    lists:reverse(Result);
action_args(Args, [ Key | Keys ], Result) ->
    action_args(Args, Keys, [ fxml:get_attr_s(Key, Args) | Result ]).

% Check arguments against rules
% max_size
check_args(_Args, _Params) ->
    lists:all(fun validsize/1, _Params).

validsize(X) when is_binary(X) ->
    case size(X) < 12000 of
        false ->
            false;

        true ->
            case utf8_utils:count(X) < 3001 of
                false ->
                    false;

                true ->
                    true
            end
    end;
validsize(_) ->
    true.
	    
% Split from private and public properties
% Private properties are for internal use only
-spec extract_message_options(
    AllProperties :: list()|binary()|{struct, list()} ) -> {list(), list()}.

extract_message_options( <<>> ) -> 
    {[], []};
extract_message_options( {struct, AllProperties} ) ->
    extract_message_options( AllProperties, [], []).

extract_message_options( [{<<"expire">>, _Value} = K | Properties], Private, Public) ->
    extract_message_options( Properties, [ K | Private ], Public);
extract_message_options( [{<<"views">>, _Value} = K | Properties], Private, Public) ->
    extract_message_options( Properties, [ K | Private ], Public);
extract_message_options( [{<<"closed">>, _Value} = K | Properties], Private, Public) ->
    extract_message_options( Properties, [ K | Private ], Public);

extract_message_options( [{ _, _} = K | Properties], Private, Public) ->
    extract_message_options( Properties, Private, [ K | Public ]);

extract_message_options( [], Private, Public) ->
    {Private, Public}.

%to_binary( Value ) ->
%    list_to_binary( integer_to_list( Value )).
%    %erlang:integer_to_binary( Value ).

-spec jid_to_username(
    Jid::#jid{}) -> binary().

jid_to_username(Jid) ->
    jlib:jid_to_string( jlib:jid_remove_resource(Jid)).

fmt_ip({A,B,C,D}) ->
    Ip = [ integer_to_list(A), 
	integer_to_list(B), 
	integer_to_list(C), 
	integer_to_list(D) 
    ],
    string:join( Ip, ".").

to(State) ->
    {<<"to">>, [
         {<<"id">>, State#state.userid},
         {<<"username">>, State#state.user}]}.

seqid() ->
    get(seqid).

seqid(Inc) ->
    Seqid = seqid(),
    put(seqid,  Seqid + Inc ).

-spec send_notification(
    State :: #state{},
    Extra :: list(),
    Class :: binary() | list(),
    Source :: binary() | list(),
    Destination :: binary() | list(),
    Token :: binary() | list(),
    Title :: binary() | list(),
    Content :: binary() | list()) -> true.

% sending an invitation to someone to connect
% create the notification in the destination userid 
%send_notification(#state{userid=Userid} = State, Extra, <<"invite">> = Class, <<"invitation">> = Source, Destination, Token, Title, Content ) ->
send_notification(#state{userid=Userid} = State, Extra, Class, Source, Destination, Token, Title, Content ) ->
    ExtraArgs = args(Extra, [<<"extra">>]), % theses extra args are NOT written in the db
    Args = [ Userid, Class, Source, Destination, Token, Title, Content ],

    ?DEBUG(?MODULE_STRING "[~5w] send_notification invite.invitation: args ~p", [ ?LINE, Args ]),
    case hyd_fqids:action(<<"notification">>, <<"create">>, Args) of % synchronous
        {error, Reason} -> 
            ?ERROR_MSG(?MODULE_STRING "[~5w] send_notification ~s.~s: error: ~p", [ ?LINE, Class, Source, Reason ]);
        
        NotificationId ->
            ?DEBUG(?MODULE_STRING "[~5w] send_notification invite.invitation: id: ~p", [ ?LINE, NotificationId ]),

            case get_user_pids(Destination, State#state.server) of
            %case get_user_pids(Userid, State#state.server) of
                [] ->
                    ?DEBUG(?MODULE_STRING "[~5w] send_notification invite.invitation: user ~p is offline, done.", [ ?LINE, Destination ]),
                    ok;

                Pids ->
                    ?DEBUG(?MODULE_STRING "[~5w] send_notification Sending to ~p, pids are: ~p", [ ?LINE, Destination, Pids ]),
                    Packet = [{<<"message">>, [
                        {<<"type">>,<<"notification">>},
                        {<<"from">>, [
                            {<<"username">>, State#state.user},
                            {<<"id">>, State#state.userid}]},
                        {<<"class">>, Class},
                        {<<"id">>, NotificationId },
                        {<<"source">>, Source},
                        {<<"bundle">>, Token},
                        {<<"extra">>, ExtraArgs},
                        {<<"header">>, Title},
                        {<<"text">>, Content},
                        {<<"persistent">>, <<"false">>}
                    ]}],
                    Me = self(),
                    lists:foreach( fun( Pid ) ->   
                        Pid ! {route, Me, Pid, {plain, Packet}}
                    end, Pids)
            end
    end.

%notification_invite(State, Args, Destination, Application, Title, Content) ->
%    send_notification(State, Args, <<"invitation">>, <<"user">>, Destination, Application, Title, Content).

notification(State, ?OPERATION_INVITECONTACT, Args, Destination, Application, Title, Content) ->
    send_notification(State, Args, <<"invite">>, <<"invitation">>, Destination, Application, Title, Content);

notification(State, ?OPERATION_ACCEPTCONTACT, Args, Destination, Application, Title, Content) ->
    send_notification(State, Args, <<"accept">>, <<"invitation">>, Destination, Application, Title, Content);

notification(State, ?OPERATION_REFUSEINVITATION, Args, Destination, Application, Title, Content) ->
    send_notification(State, Args, <<"refuse">>, <<"invitation">>, Destination, Application, Title, Content);

notification(State, ?OPERATION_DELETECONTACT, Args, Destination, Application, Title, Content) ->
    send_notification(State, Args, <<"delete">>, <<"contact">>, Destination, Application, Title, Content);

notification(_State, _Op, _, _, _, _, _) ->
    ok.

-spec delivered_notification( 
    State :: #state{},
    Fqid :: binary(),
    Infos :: list() ) -> ok.

delivered_notification(#state{user=_Username, sid=_Sid, userid=Userid, server=Server}, Fqid, Args ) ->
    ?DEBUG(?MODULE_STRING "\n\nArgs: ~p\n\n", [ Args ]),

    case args( Args, [<<"info">>]) of
        [ Infos ] ->
            case args( Infos, [ <<"author">>, <<"parent">> ]) of
                [ Userid, _ ] ->
                    % don't send delivered notification when author read his own message...
                    ok;

                [ Author, Parent ] ->
                    case get_user_pids(Author, Server) of
                        [] ->
                            ok;

                        Pids ->
                            ?DEBUG(?MODULE_STRING " delivered_notification Sending to ~p, pids are: ~p", [ Author, Pids ]),
                            Packet = [{<<"message">>, [
                                {<<"type">>,<<"delivery">>},
                                {<<"userid">>, Userid},
                                %{<<"from">>, [
                                %    {<<"username">>, State#state.user},
                                %    {<<"id">>, State#state.userid}]},
                                {<<"id">>, Fqid},
                                {<<"parent">>, Parent}
                            ]}],
                            Me = self(),
                            lists:foreach( fun( Pid ) ->   
                                Pid ! {route, Me, Pid, {plain, Packet}}
                            end, Pids)
                    end;

                _ ->
                    ok
            end;

         _ ->
            ok
    end.

-spec action_trigger( 
    State :: #state{},
    Element :: binary(),
    Infos :: list(),
    Action :: binary(),
    Args :: list(),
    Result :: binary() | list() ) -> ok.

action_trigger(State, Element, Infos, Action, Args, Result) ->
    case args(Infos, [49]) of % extract the type of element i.e. group or thread or message ...
        [ Type ] ->
            action(State, Element, Type, Action, Args, Result);
        [] ->
            action(State, Element, Infos, Action, Args, Result)
    end.

-spec action( 
    State :: #state{},
    Element :: binary(),
    Type :: binary(),
    Action :: binary(),
    Args :: list(),
    Result :: binary() | list() ) -> ok.

action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"addRead">>, [Parent], _Result) when 
    Type =:= <<"message">>;
    Type =:= <<"photo">> ->

    ?DEBUG(?MODULE_STRING "[~5w] [~s (~p|~p)] action ~p ~p:~p(~p): ~p", [ ?LINE, _Username, seqid(), _Sid, Element, Type, "addRead", [Parent], _Result ]),

    RoomType = 0,
    mod_chat:create_room(Host, RoomType, Creator, Parent, []), % this will create synchronously the room if needed
    Packet = make_packet( _State, <<"event">>, [
        { <<"read">>, Element}
    ]),
    mod_chat:route(Host, Parent, Creator, message, Packet);

action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"addMember">>, [Otherid], Result) when 
    Type =:= <<"group">>;
    Type =:= <<"thread">> ->

    ?DEBUG(?MODULE_STRING "[~5w] [~s (~p|~p)] action ~p ~p:~p(~p): ~p", [ ?LINE, _Username, seqid(), _Sid, Element, Type, "addmember", [Otherid], Result ]),

    mod_chat:route(Host, Element, Creator, add, [Otherid]);

action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"delMember">>, [Otherid], Result) when 
    Type =:= <<"conversationgroup">>;
    Type =:= <<"group">>;
    Type =:= <<"thread">> ->

    ?DEBUG(?MODULE_STRING "[~5w] [~s (~p|~p)] action ~p ~p:~p(~p): ~p", [ ?LINE, _Username, seqid(), _Sid, Element, Type, "delmember", [Otherid], Result ]),

    mod_chat:route(Host, Element, Creator, del, [Otherid]);

action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"delChild">>, [Child], _) when 
    Type =:= <<"group">>;
    Type =:= <<"thread">> ->

    RoomType = 0,
    mod_chat:create_room(Host, RoomType, Creator, Element, []), % this will create synchronously the room if needed
    Packet = make_packet( _State, <<"del">>, [
        { <<"parent">>, Element},
        { <<"child">>, Child}]),
    mod_chat:route(Host, Element, Creator, message, Packet);

action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"addChild">>, [Child], [Count]) when 
    Type =:= <<"group">>;
    Type =:= <<"drop">>;
    Type =:= <<"thread">> ->

    RoomType = 0,
    mod_chat:create_room(Host, RoomType, Creator, Element, []), % this will create synchronously the room if needed
    Packet = make_packet( _State, <<"add">>, [
        { <<"parent">>, Element},
        { <<"count">>, Count},
        { <<"child">>, Child}]),
    mod_chat:route(Host, Element, Creator, message, Packet);

action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"addChild">>, [Child], [Count]) when 
    Type =:= <<"conversationgroup">>;
    Type =:= <<"conversation">> ->

    RoomType = 0,
    mod_chat:create_room(Host, RoomType, Creator, Element, []), % this will create synchronously the room if needed
    Packet = make_packet( _State, <<"add">>, [
        { <<"parent">>, Element},
        { <<"count">>, Count},
        { <<"child">>, Child}]),
    mod_chat:route(Host, Element, Creator, message, Packet);

% when an addChild has been processed in a page, comgroup, or timeline, this new child must be forwarded to
% all subscribers of this page, comgroup or timeline.
action(#state{user=_Username, sid=_Sid, userid=Creator, server=Host} = _State, Element, Type, <<"addChild">>, [Child], [Count]) when 
    Type =:= <<"page">>;
    Type =:= <<"comgroup">>;
    Type =:= <<"timeline">> ->

    RoomType = Type,
    mod_chat:create_room(Host, RoomType, Creator, Element, []), % this will create synchronously the room if needed
    Packet = make_packet( _State, <<"add">>, [
        { <<"parent">>, Element},
        { <<"count">>, Count},
        { <<"child">>, Child}]),
    mod_chat:route(Host, Element, Creator, message, Packet);

% realtime messages for article childs FEATURE IS POSTPONED
% action(#state{user=Username, userid=Creator, server=Host} = _State, Element, Type, <<"addChild">>, [Child], _Result) when
%     Type =:= <<"article">> ->
% 
%     RoomType = Type,
%     mod_chat:create_room(Host, RoomType, Creator, Element, []), % this will create synchronously the room if needed
%     Packet = make_packet( _State, <<"event">>, [
%         { <<"new">>, Element}
%     ]),
%     mod_chat:route(Host, Element, Creator, message, Packet),
%     mod_chat:route(Host, Element, Creator, add, [Creator]);

action(#state{user=_Username, sid=_Sid} = _State, _Element, _Type, _Action, _Args, _Result) ->
    ?DEBUG(?MODULE_STRING "[~5w] default: action on type '~p': Element: '~p' Action: '~p' Args: '~p' Result: '~p'", [ ?LINE, _Type, _Element, _Action, _Args, _Result ]),
    ok.

ok( Do, Success ) ->
    case Do() of
        {ok, true} ->
            Success();
        _Any ->
            _Any
    end.

handle(<<"subscriptions">> = Type, Operation, SeqId, Args, State) ->
    case subscription_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING "[~5w] handle_~p (default): Operation: ~p, Args: ~p", [ ?LINE, Type, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call ">>),
            send_element(State, Answer);

        OperationId ->
            #jid{luser=User} = State#state.jid,
            Response = do_subscription(OperationId, User, SeqId, Args, State),
            handle_operation(Type, SeqId, Response, State)
    end;

handle(<<"pages">> = Type, Operation, SeqId, Args, State) ->
    case page_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING "[~5w] handle_~p (default): Operation: ~p, Args: ~p", [ ?LINE, Type, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call ">>),
            send_element(State, Answer);

        OperationId ->
            #jid{luser=User} = State#state.jid,
            Response = do_subscription(OperationId, User, SeqId, Args, State),
            handle_operation(Type, SeqId, Response, State)
    end;    

handle(<<"comgroups">> = Type, Operation, SeqId, Args, State) ->
    case comgroup_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING ".~p handle_~p (default): Operation: ~p, Args: ~p", [ ?LINE, Type, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call ">>),
            send_element(State, Answer);

        OperationId ->
            #jid{luser=User} = State#state.jid,
            Response = do_comgroup(OperationId, User, SeqId, Args, State),
            handle_operation(Type, SeqId, Response, State)
    end;    

handle(<<"admin">> = Type, Operation, SeqId, Args, #state{ sasl_state = Level } = State) when Level >= ?ROLE_SUPERVISOR ->
    case admin_operations(Operation) of
        false ->
            ?DEBUG(?MODULE_STRING ".~p handle_~p Admin (default): Operation: ~p, Args: ~p", [ ?LINE, Type, Operation, Args ]),
            Answer = make_error(SeqId, 404, <<"unknown call ">>),
            send_element(State, Answer);

        OperationId ->
            #jid{luser=User} = State#state.jid,
            Response = do_admin(OperationId, User, SeqId, Args, State),
            handle_operation(Type, SeqId, Response, State)
    end;    

handle(Type, Operation, SeqId, Args, State) ->
    ?DEBUG(?MODULE_STRING ".~p handle (default): Type: ~p Operation: ~p, Args: ~p", [ ?LINE, Type, Operation, Args ]),
    Answer = make_error(SeqId, 404, <<"unknown call ">>),
    send_element(State, Answer).

handle_operation(Type, SeqId, Response, State) ->
    case Response of
        [] ->
            Answer = make_answer(SeqId, [{<<"result">>, []},{<<"code">>,404}]),
            send_element(State, Answer);

        false -> % error is handled by the operation
            ok;

        true ->
            Answer = make_answer(SeqId, [{<<"result">>, <<"ok">>}]),
            send_element(State, Answer);

        {ok, []} ->
            Answer = make_answer(SeqId, 204, []), % HTTP 204 No Content
            send_element(State, Answer);
            
        {ok, true} ->
            Answer = make_answer(SeqId, 200, [
                {<<"result">>, <<"true">>}
            ]),
            send_element(State, Answer);

        {ok, false} ->
            Answer = make_answer(SeqId, 200, [
                {<<"result">>, <<"false">>}
            ]),
            send_element(State, Answer);
            
        {ok, Result} ->
            Answer = make_answer(SeqId, 200, [
                {<<"result">>, Result}
            ]),
            send_element(State, Answer);

        {error, Reason} -> 
            ?ERROR_MSG(?MODULE_STRING ".~p handle_~s error: ~p", [ ?LINE, Type, Reason ]),
            Answer = make_error(Reason, SeqId, undefined, undefined),
            send_element(State, Answer);

        Result ->
            ?ERROR_MSG(?MODULE_STRING " handle_~s returns: ~p", [Type, Result]),
            Answer = make_answer(SeqId, [{<<"result">>, Result}]),
            send_element(State, Answer)
    end.


handle_query(Operation, SeqId, Args, State) ->
    case args(Args, [<<"to">>]) of
        [ Element ] = Params ->
            ?DEBUG(?MODULE_STRING "[~5w] handle_Action: operation: ~p, on Element: ~p", [ ?LINE, Operation, Element] ),
            Module = <<"init">>, % specific module for initialisation
            hyd_fqids:action_async(SeqId, Module, Operation, [ 0 | Params ]),
            Actions = State#state.aux_fields,
            State#state{aux_fields=[{SeqId, [ Element, Operation, Params ]} | Actions ]};

            %?DEBUG(?MODULE_STRING "[~5w] handle_action ActionArgs: ~p, Args: ~p, -> Params: ~p", [ ?LINE, ActionArgs, Args, Params ]),
            %% ActionArgs = [<<"application">>],
            %% Params = action_args(Args, ActionArgs),
            %% case check_args(ActionArgs, Params) of
            %%     true ->
            %%         ?DEBUG(?MODULE_STRING "[~5w] handle_action ActionArgs: ~p, Args: ~p, -> Params: ~p", [ ?LINE, ActionArgs, Args, Params ]),
            %%         hyd_fqids:action_async(SeqId, Element, Operation, [ 0 | Params ]),
            %%         Actions = State#state.aux_fields,
            %%         State#state{aux_fields=[{SeqId, [ Element, Operation, Params ]} | Actions ]};

            %%     false ->
            %%         Answer = make_error(SeqId, 406, <<"invalid arguments provided">>),
            %%         send_element(State, Answer),
            %%         State
            %% end;
                
        _ ->
            Answer = make_error(SeqId, 406, <<"missing arguments: to">>),
            send_element(State, Answer),
            State
    end.

send_message( #state{server=Server} = State, Contacts, Message) when is_list(Contacts) ->
    lists:foreach(fun(Contact) ->
        case get_user_pids(Contact,Server) of
            [] ->
                ok;

            Pids ->
                ?DEBUG(?MODULE_STRING " [~s]: send_message '~p' to ~s@~s's pids: ~p", [
                    State#state.user,
                    Message, Contact, Server, Pids ]),

                lists:foreach(fun(Pid) ->
                    Pid ! {status, State#state.userid, State#state.user, Message}
                end, Pids)

           end end, Contacts);
send_message( State, Contact, Message) ->
    send_message( State, [Contact], Message).
