_ = require("underscore")
express = require("express")
ejs = require("ejs")
restful = require("node-restful")
url = require("url")
mongoose = restful.mongoose
Project = require("./models/project")
Theme = require("./models/theme")
User = require("./models/user")
Phases = require("./models/phases")
EventSchema = require("./models/event")
AdminRoutes = require("./routes/admin")

# logging template
logTmpl = ejs.compile('<%= date %> (<%= response_time %>ms): ' +
                          '<%= status %> <%= method %> <%= url %>');

app = express()

app.resource = Project

# app.use cors()
app.use express.bodyParser()
app.use express.cookieParser()
app.use express.session
  secret: 'personasecret'
app.use express.query()
app.use (req, res, next) ->
  rEnd = res.end

  # To track response time
  req._rlStartTime = new Date()

  # Setup the key-value object of data to log and include some basic info
  req.kvLog =
    date: req._rlStartTime.toISOString()
    method: req.method
    url: url.parse(req.originalUrl).pathname

  # Proxy the real end function
  res.end = (chunk, encoding) ->
    # Do the work expected
    res.end = rEnd
    res.end chunk, encoding

    # And do the work we want now (logging!)

    # Save a few more variables that we can only get at the end
    req.kvLog.status = res.statusCode
    req.kvLog.response_time = (new Date() - req._rlStartTime)

    # Print the log
    #if (res.statusCode != 200 && res.statusCode != 304)
    console.log logTmpl(req.kvLog)

  next()



app.set('views', __dirname + '/app/dist');
app.engine('html', ejs.renderFile);
app.use(express.static(__dirname + '/app/dist'));

PORT = process.env.PORT || process.env.VCAP_APP_PORT || 3000
HOST = process.env.IP_ADDRESS || process.env.VCAP_APP_HOST || '127.0.0.1'

# Must match your browser's address bar
audience = 'http://' + HOST + ':' + PORT

require('express-persona') app,
  audience: audience

mongoose.connect "mongodb://localhost/projects"

isLoggedIn = (req, res, next) ->
  if req.session.email
    res.logged_in_email = req.session.email
    next()
  else
    res.send 'Not Authenticated'
    next()

authProject = (req, res, next) ->
  isLoggedIn req, res, ->
    project = Project.findOne({_id:req.params.id}).populate('owner').exec (err, doc) ->
      if doc.owner.email is req.session.email or getAuthLevel(req.session.email) is 3
        next()
      else
        res.send 'Not Authorized'

authTheme = (req, res, next) ->
  isLoggedIn req, res, ->
    theme = Theme.findOne({_id:req.params.id}).populate('owner').exec (err, doc) ->
      if doc.owner.email is req.session.email or getAuthLevel(req.session.email) is 3
        next()
      else
        res.send 'Not Authorized'

authUser = (req, res, next) ->
  isLoggedIn req, res, ->
    User.findOne({_id: req.params.id}).exec (err, doc) ->
      if req.session.email is doc.email
        next()
      else
        res.send 'Not Authorized'

isAdmin = (req, res, next) ->
  isLoggedIn req, res, ->
    next()

# server side auth on projects
Project.before('post', isAdmin)
Project.before('put', authProject)
Project.before('delete', authProject)
Theme.before('post', isAdmin)
Theme.before('put', authTheme)
Theme.before('delete', authTheme)
User.before('put', authUser)

Project.before 'get', (req, res, next) ->
  # override node-restful and populate the themes
  id = req.route.params.id
  if id
    Project.findOne({_id: id}).populate('themes').populate('owner').exec (err, docs) ->
      res.send docs
  else
    Project.find().populate('themes').populate('owner').exec (err, docs) ->
      res.send docs

Project.after 'put', (req, res, next) ->
  Project.findOne({_id: res.locals.bundle._id}).populate('themes').populate('owner').exec (err, doc) ->
    res.send doc

Theme.before 'get', (req, res, next) ->
  # add related projects to theme response if querying one theme
  if req.params.id
    Theme.findOne({_id: req.params.id}).populate('owner').exec (err, doc) ->
      Project.find({themes: doc._id}).populate('themes').populate('owner').exec (err, docs) ->
        res.send
          theme: doc
          projects: docs
  else
    Theme.find().populate('owner').exec (err, docs) ->
      res.send docs

Project.route "total.get", (req, res) ->
  Project.find {}, (err, docs) ->
    res.send {total: docs.length}

Project.register app, "/api/projects"
Theme.register app, "/api/themes"
User.register app, "/api/users"

app.get "/api/:email/projects", (req, res) ->
  User.findOne({email: req.params.email}).exec (err, doc) ->
    Project.find({"owner": doc._id}).populate('owner').populate('themes').exec (err, projects) ->
      res.send projects

app.get "/api/:email/collaborations", (req, res) ->
  Project.where("collaborators.email", req.params.email).populate('themes').populate('owner').exec (err, collaborations) ->
    res.send collaborations

app.get "/api/:email/themes", (req, res) ->
  User.findOne({email: req.params.email}).exec (err, doc) ->
    Theme.find({"owner": doc._id}).exec (err, docs) ->
      res.send docs

app.get "/api/phase/:id", (req, res) ->
  Project.find {phase: req.params.id},  (err, docs) ->
    res.send docs

app.get "/api/phases", (req, res) ->
    for phase in Phases
      phase.count = 0
    Project.aggregate
      $group:
        _id: "$phase"
        count:
          $sum : 1
      , (err, docs) ->
        for doc in docs
          Phases[doc._id].count = doc.count
        res.send Phases

index = (req, res) -> res.render 'index.html'

# Angular Routes
app.get "/", index
app.get "/profile", index
app.get "/projects", index
app.get "/projects/new", index
app.get "/:email/projects", index
app.get "/:email/themes", index
app.get "/project/:projectId", index
app.get "/project/:projectId/edit", index
app.get "/project/:projectId/:phaseId", index
app.get "/phase/:phaseId", index
app.get "/themes", index
app.get "/themes/new", index
app.get "/theme/:themeId", index
app.get "/401", index

# admin
app.get "/admin/dump", AdminRoutes.dump
app.post "/admin/load", AdminRoutes.load

# Auth Levels
# 0 : Public (no write/delete)
# 1 : Not Used
# 2 : Editor (can create/delete/edit own models)
# 3 : Admin  (all access)

# whitelist of admin emails
adminWhitelist = ['darrin', 'dhenein']

getAuthLevel = (email) ->
  [username, domain] = email.split '@'
  if domain = 'mozilla.org' or 'mozilla.com' or 'mozillafoundation.org'
    if _.contains adminWhitelist, username
      return 3
    else
      return 2
  return 0

# auth user
app.get "/getUser", (req, res) ->
  if req.session.email
    User.findOne({email: req.session.email}).exec (err, doc) ->
      if doc
        doc.authLevel = getAuthLevel doc.email
        res.send doc
      else
        User.create {
          email: req.session.email
        }, (err, user) ->
          user.authLevel = getAuthLevel user.email
          res.send user
  else
    res.send {error: 'Not logged in'}

console.log "Listening at #{HOST}:#{PORT}..."
app.listen PORT, HOST