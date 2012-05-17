class App
  express = require 'express'
  redis = require 'redis'
  uuid = require 'node-uuid'
  RedisStore = require('connect-redis')(express)
  sessionStore = new RedisStore()
  messageStore = redis.createClient()

  # These will be used only on ioController()
  fs = require 'fs'
  parseCookie = require('connect').utils.parseCookie

  constructor:->
    @initAndConfigureApp()
    @runApp()
    @ioController()

  initAndConfigureApp:->
    @app = module.exports = express.createServer()

    @app.configure () =>
      @app.use express.bodyParser()
      @app.use express.cookieParser()
      @app.use express.session(
        secret: "POIUYhjnmp)(*&^%rtghbnmlkoi987654ertfghi;lkjhgfPOIUHN"
        store: sessionStore # Instead of the regular `new RedisStore()`
      )
      @app.use(express.static(__dirname + '/public'))
      @app.set "views", __dirname + "/views"
      @app.set "view engine", "jade"
      @app.set "view options", pretty: true

    @app.get "/controller", (req, res) ->
      nowpage = 1
      if req.session.nowpage?
        nowpage = req.session.nowpage
      req.session.nowpage = nowpage
      res.render "controller", layout: false, nowpage: nowpage

    @app.get "/showoff", (req, res) ->
      if req.session.nickname?
        nickname = req.session.nickname
      res.render "showoff", layout: false, nickname: nickname

    @app.post "/chat", (req, res) ->
      if not req.session.nickname
        req.session.nickname = req.body.nickname
        req.session.hkey = uuid.unparse uuid.v1({}, [], 16), 16
        console.info req.session.hkey
        messageStore.hmset req.session.hkey, {
          "nickname": req.body.nickname,
          "created": new Date().getTime()
        }, (err, res) ->
          console.info err
          console.info res
      else
        req.session.nickname = req.body.nickname
        sessionStore.set req.cookies['connect.sid'], req.session, (err) ->
          console.info err

      res.send(req.body)

    @app.get "/", (req, res) ->
      if req.session.nickname?
        nickname = req.session.nickname

      res.render "index", layout: false, nickname: nickname

  runApp:->
    port = process.env.PORT || 3000
    @app.listen port, =>
      console.info "Express server listening on port #{@app.address().port} in #{@app.settings.env} mode"

  ioController:->
    @io = require('socket.io').listen @app

    @io.configure () =>
      @io.enable "browser client minification"
      @io.enable "browser client etag"
      @io.enable "browser client gzip"
      @io.set "log level", 1
      @io.set "transports", [
        "xhr-polling"
      ]

      @io.set 'authorization', (data, callback) =>
        if data.headers.cookie?
          data.cookie = parseCookie data.headers.cookie
          data.sessID = data.cookie['connect.sid']
          sessionStore.get data.sessID, (err, session) =>
            if err or not session
              callback new Error "There's no session"
            else
              callback null, true
        else
          callback new Error "No cookie transmitted!"

      path = require "path"
      HTTPPolling = require(path.join(path.dirname(require.resolve('socket.io')), 'lib', 'transports', 'http-polling'))
      XHRPolling = require(path.join(path.dirname(require.resolve('socket.io')), 'lib', 'transports', 'xhr-polling'))
      XHRPolling.prototype.doWrite = (data)->
        HTTPPolling.prototype.doWrite.call(@)
        headers =
          'Content-Type': 'text/plain; charset=utf-8'
          'Content-Length': (data and Buffer.byteLength(data)) or 0

        if @req.headers.origin
          headers['Access-Controll-Allow-Origin'] = '*'
          if @req.headers.cookie
            headers['Access-Controll-Allow-Credentials'] = 'true'

        @response.writeHead 200, headers
        @response.write data
        console.info @name+' writting', data

    @io.on 'connection', (client) =>
      console.info "Got connected to server!"

      hs = client.handshake
      hkey = uuid.unparse uuid.v1({}, [], 16), 16
      nowpage = 1

      if hs.headers.cookie?
        cookie = parseCookie hs.headers.cookie
        sessionStore.get cookie['connect.sid'], (err, session) =>
          if not err or err is null or session
            hkey = session.hkey
            nowpage = session.nowpage

      client.on "drawClick", (data) ->
        client.broadcast.emit "draw", {
          x: data.x,
          y: data.y,
          type: data.type
        }

      client.on "control-slide", (data, fn) ->
        nowpage = data.page
        hs = client.handshake
        if hs.headers.cookie?
          cookie = parseCookie hs.headers.cookie
          sessionStore.get cookie['connect.sid'], (err, session) =>
            if not err or err is null or session
              session.nowpage = nowpage
              sessionStore.set cookie['connect.sid'], session, ()->
                console.info arguments
              console.info session, data.page

        client.broadcast.emit "slide", page: data.page

      client.on "message", (data, fn) ->
        messageStore.hlen hkey, (err, res) ->
          mlength = if not err and res > 0 then res/2 else 1
          messageData = {}
          messageData['msg'+mlength.toString()] = data.message
          messageData['ts'+mlength.toString()] = new Date()
          messageStore.hmset hkey, messageData, (err, res) =>
            client.broadcast.emit "message", {
              nickname: data.nickname,
              message: data.message
            }
          messageData = null
        fn data.message

      client.on "disconnect", (data) ->

# Start the class!!
app = new App()
