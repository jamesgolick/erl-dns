-module(erldns_app).
-behavior(application).

% Application hooks
-export([start/2, stop/1]).

%%% Application, this is a work-in-progress

start(Type, Args) ->
  lager:info("~p:start(~p, ~p)~n", [?MODULE, Type, Args]),
  erldns_sup:start_link().

stop(State) ->
  lager:info("~p:stop(~p)~n", [?MODULE, State]),
  ok.
