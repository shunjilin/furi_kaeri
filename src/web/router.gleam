import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{None, Some}
import group_registry.{type GroupRegistry}
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}
import web/server.{type StateMsg}
import web/view

pub type Context {
  Context(registry: GroupRegistry(view.SharedMsg), manager: Subject(StateMsg))
}

pub fn handle_request(
  req: Request(Connection),
  ctx: Context,
) -> Response(ResponseData) {
  case request.path_segments(req) {
    [] -> serve_html()
    ["lustre", "runtime.mjs"] -> serve_runtime()
    ["ws"] -> serve_board(req, ctx)
    _ -> not_found()
  }
}

fn serve_html() -> Response(ResponseData) {
  let body =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width"),
        ]),
        html.title([], "Furi Kaeri"),
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
      ]),
      html.body([attribute.style("height", "100dvh")], [
        server_component.element([server_component.route("/ws")], []),
      ]),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(body))
  |> response.set_header("content-type", "text/html")
}

fn serve_runtime() -> Response(ResponseData) {
  let assert Ok(priv) = application.priv_directory("lustre")
  let path = priv <> "/static/lustre-server-component.min.mjs"

  case mist.send_file(path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.prepend_header("content-type", "application/javascript")
      |> response.set_body(file)
    Error(_) -> not_found()
  }
}

fn serve_board(req: Request(Connection), ctx: Context) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) {
      let component = view.component(ctx.manager)
      let assert Ok(runtime) =
        lustre.start_server_component(component, ctx.registry)

      let self = process.new_subject()
      let selector = process.new_selector() |> process.select(self)

      server_component.register_subject(self) |> lustre.send(to: runtime)

      #(SocketState(runtime, self), Some(selector))
    },
    handler: loop_socket,
    on_close: fn(state) { lustre.shutdown() |> lustre.send(to: state.runtime) },
  )
}

type SocketState {
  SocketState(
    runtime: lustre.Runtime(view.Msg),
    self: Subject(server_component.ClientMessage(view.Msg)),
  )
}

fn loop_socket(state: SocketState, msg, conn) {
  case msg {
    mist.Text(json) -> {
      let decoder = server_component.runtime_message_decoder()
      case json.parse(json, decoder) {
        Ok(action) -> lustre.send(state.runtime, action)
        Error(_) -> Nil
      }
      mist.continue(state)
    }
    mist.Custom(client_msg) -> {
      let json = server_component.client_message_to_json(client_msg)
      let _ = mist.send_text_frame(conn, json.to_string(json))
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
    _ -> mist.continue(state)
  }
}

fn not_found() {
  response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
}
