-module(erldns_udp_server).

-include("dns_records.hrl").

-behavior(gen_server).

% API
-export([start_link/0]).

% Gen server hooks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
  ]).

-define(SERVER, ?MODULE).
-define(MAX_PACKET_SIZE, 512).

-record(state, {port=53}).

%% Public API
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% gen_server hooks
init(_Args) ->
  {ok, Port} = application:get_env(erldns, port),
  spawn(fun() -> start(Port) end),
  {ok, #state{port = Port}}.
handle_call(_Request, _From, State) ->
  {ok, State}.
handle_cast(_Message, State) ->
  {noreply, State}.
handle_info(_Message, State) ->
  {noreply, State}.
terminate(_Reason, _State) ->
  ok.
code_change(_PreviousVersion, State, _Extra) ->
  {ok, State}.

%% Internal functions
%% Start a UDP server.
start(Port) ->
  random:seed(erlang:now()),
  case gen_udp:open(Port, [binary]) of
    {ok, Socket} -> 
      lager:info("UDP server opened socket: ~p~n", [Socket]),
      loop(Socket);
    {error, eacces} ->
      lager:error("Failed to open UDP socket. Need to run as sudo?"),
      {error, eacces}
  end.

%% Loop for accepting UDP requests
loop(Socket) ->
  lager:info("Awaiting Request~n"),
  receive
    {udp, Socket, Host, Port, Bin} ->
      lager:info("Received UDP Request~n"),
      spawn(fun() -> handle_dns_query(Socket, Host, Port, Bin) end),
      loop(Socket)
  end.

%% Handle DNS query that comes in over UDP
handle_dns_query(Socket, Host, Port, Bin) ->
  %% TODO: measure
  DecodedMessage = dns:decode_message(Bin),
  lager:info("Decoded message ~p~n", [DecodedMessage]),
  Response = erldns_handler:handle(DecodedMessage),
  EncodedMessage = dns:encode_message(Response),
  BinLength = byte_size(EncodedMessage),
  gen_udp:send(Socket, Host, Port, 
    optionally_truncate(Response, EncodedMessage, BinLength)).

%% Determine the max payload size by looking for additional
%% options passed by the client.
max_payload_size(Message) ->
  case Message#dns_message.additional of
    [Opt|_] ->
      case Opt#dns_optrr.udp_payload_size of
        [] -> ?MAX_PACKET_SIZE;
        _ -> Opt#dns_optrr.udp_payload_size
      end;
    _ -> ?MAX_PACKET_SIZE
  end.

%% Truncate the message and encode if necessary.
optionally_truncate(Message, EncodedMessage, BinLength) ->
  case BinLength > max_payload_size(Message) of
    true -> dns:encode_message(truncate(Message));
    false -> EncodedMessage
  end.

%% Truncate the message for UDP packet limitations (at least that
%% is what it may eventually do. Right now it simply sets the
%% tc bit to indicate the message was truncated.
truncate(Message) ->
  lager:info("Message was truncated: ~p", [Message]),
  %Response = erldns_handler:build_response(Message#dns_message.answers, Message),
  Message#dns_message{tc = true}.
