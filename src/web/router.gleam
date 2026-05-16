import domain/user
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import group_registry.{type GroupRegistry}
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}
import web/group_manager
import web/views/board as board_view
import youid/uuid

const user_id_key: String = "user_id"

pub type Context {
  Context(
    registry: GroupRegistry(board_view.SharedMsg),
    group_manager: Subject(group_manager.Message),
  )
}

type GetUserResult {
  NewUser(user.User)
  ExistingUser(user.User)
}

fn get_user(req: Request(Connection)) -> GetUserResult {
  let result =
    req
    |> request.get_cookies
    |> list.find_map(fn(cookie) {
      case cookie {
        #(key, user_id_string) if key == user_id_key -> {
          user_id_string
          |> uuid.from_string()
          |> result.map(fn(uuid) { user.new(user.UserId(uuid)) })
        }
        _ -> Error(Nil)
      }
    })

  case result {
    Ok(user) -> ExistingUser(user)
    Error(Nil) -> NewUser(user.new(user.gen_id()))
  }
}

pub fn handle_request(
  req: Request(Connection),
  ctx: Context,
) -> Response(ResponseData) {
  let user_result = get_user(req)

  let user = case user_result {
    NewUser(user) -> {
      user
    }
    ExistingUser(user) -> user
  }

  case request.path_segments(req), req.method {
    [], http.Get -> serve_landing_layout() |> serve_page(user_result)
    ["board", board_id], http.Get -> {
      case group_manager.get_board(ctx.group_manager, board_id) {
        Ok(_) -> serve_board_layout(board_id) |> serve_page(user_result)
        Error(group_manager.BoardDoesNotExist) ->
          response.new(404)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string("Board not found.")),
          )
      }
    }
    ["board", "create"], http.Post -> handle_create_board(ctx)
    ["static", "css", "main.css"], http.Get ->
      serve_static("priv/static/css/main.css", "text/css")
    ["static", "js", "client.mjs"], http.Get ->
      serve_static("priv/static/js/client.mjs", "text/javascript")
    ["lustre", "runtime.mjs"], http.Get -> serve_runtime()
    ["board", board_id, "ws"], http.Get ->
      serve_board_page(req, ctx, user, board_id)
    _, _ -> not_found()
  }
}

fn cookie_attributes() {
  cookie.Attributes(
    // 12 hours
    option.Some(60 * 60 * 12),
    option.Some(""),
    option.None,
    // TODO: configure by env
    False,
    True,
    option.Some(cookie.Strict),
  )
}

fn handle_create_board(ctx: Context) -> Response(ResponseData) {
  let board_id = uuid.v7() |> uuid.to_string()
  case group_manager.create_board(ctx.group_manager, board_id) {
    Ok(_) -> {
      response.new(303)
      |> response.set_header("location", "/board/" <> board_id)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
    }
    Error(group_manager.BoardAlreadyExist) -> {
      response.new(500)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("Failed to create board.")),
      )
    }
  }
}

fn serve_static(path: String, mime_type: String) -> Response(ResponseData) {
  mist.send_file(path, offset: 0, limit: None)
  |> result.map(fn(file) {
    response.new(200)
    |> response.prepend_header("content-type", mime_type)
    |> response.prepend_header("cache-control", "public, max-age=3600")
    |> response.set_body(file)
  })
  |> result.lazy_unwrap(fn() { not_found() })
}

fn serve_page(
  html_body: bytes_tree.BytesTree,
  user_result: GetUserResult,
) -> Response(ResponseData) {
  response.new(200)
  |> response.set_body(mist.Bytes(html_body))
  |> response.set_header("content-type", "text/html")
  |> assign_user(user_result)
}

fn serve_board_layout(board_id: String) -> bytes_tree.BytesTree {
  let ws_route = "/board/" <> board_id <> "/ws"

  let extra_head = [
    html.script(
      [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
      "",
    ),
    html.script(
      [attribute.type_("module"), attribute.src("/static/js/client.mjs")],
      "",
    ),
  ]

  let body_content = [
    server_component.element([server_component.route(ws_route)], []),
  ]

  layout("Board", extra_head, body_content)
}

fn serve_landing_layout() -> bytes_tree.BytesTree {
  let body_content = [
    html.main([], [
      html.h1([], [html.text("Welcome")]),
      html.form([attribute.method("POST"), attribute.action("/board/create")], [
        html.button(
          [
            attribute.type_("submit"),
          ],
          [html.text("Create New Board")],
        ),
      ]),
    ]),
  ]

  // Pass an empty list for extra_head since it only needs core defaults
  layout("Home", [], body_content)
}

fn layout(
  title_suffix: String,
  page_specific_head: List(element.Element(msg)),
  body_content: List(element.Element(msg)),
) -> bytes_tree.BytesTree {
  html([attribute.lang("en")], [
    html.head([], [
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/css/main.css"),
      ]),
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width"),
      ]),
      html.title([], "Furi Kaeri - " <> title_suffix),
      ..page_specific_head
    ]),
    html.body([attribute.style("height", "100dvh")], body_content),
  ])
  |> element.to_document_string_tree
  |> bytes_tree.from_string_tree
}

fn assign_user(
  response: Response(ResponseData),
  user_result: GetUserResult,
) -> Response(ResponseData) {
  case user_result {
    NewUser(user) -> {
      let user.UserId(uuid) = user.id(user)
      response.set_cookie(
        response,
        user_id_key,
        uuid.to_string(uuid),
        cookie_attributes(),
      )
    }
    ExistingUser(_) -> {
      response
    }
  }
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

fn serve_board_page(
  req: Request(Connection),
  ctx: Context,
  user: user.User,
  board_id: String,
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) {
      // we already guard in the router before serving the page
      // so we can assert here
      let assert Ok(board_manager) =
        group_manager.get_board(ctx.group_manager, board_id)
      let component = board_view.component(board_manager, user, board_id)
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
    runtime: lustre.Runtime(board_view.Msg),
    self: Subject(server_component.ClientMessage(board_view.Msg)),
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
