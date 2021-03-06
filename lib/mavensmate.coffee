{$, $$, $$$, EditorView, View} = require 'atom'
fs    = require 'fs'
path  = require 'path'
{Subscriber,Emitter} = require 'emissary'
# mavensmate                          = require 'mavensmate'
MavensMateConfig                    = require('./mavensmate-config').config
MavensMateEventEmitter              = require('./mavensmate-emitter').pubsub
MavensMateCoreAdapter               = require('./mavensmate-core-adapter')
MavensMateProjectListView           = require './mavensmate-project-list-view'
MavensMateErrorMarkers              = require './mavensmate-error-markers'
MavensMatePanelView                 = require('./panel/panel-view').panel
MavensMateStatusBarView             = require './mavensmate-status-bar-view'
MavensMateLogFetcher                = require './mavensmate-log-fetcher'
FileSystemWatcher                   = require './watchers/fs-watcher'
tracker                             = require('./mavensmate-promise-tracker').tracker
util                                = require './mavensmate-util'
emitter                             = require('./mavensmate-emitter').pubsub
commands                            = require './commands.json'
{exec}                              = require 'child_process'
ErrorsView                          = require './mavensmate-errors-view'
atom.mavensmate = {}
window.jQuery = $

require '../scripts/bootstrap'

errorsView = null

createErrorsView = (params) ->
  errorsView = new ErrorsView(params)

errorsDeserializer =
  name: 'MavensMateErrorsView'
  version: 1
  deserialize: (state) ->
    createErrorsView(state) if state.constructor is Object
atom.deserializers.add(errorsDeserializer)

MavensMateAtomWatcher = require('./watchers/atom-watcher').watcher
MavensMateTabView = null
MavensMateServerView = null

tabViewUri = 'mavensmate://tabView'
createTabView = (params) ->
  MavensMateTabView ?= require './mavensmate-tab-view'
  tabView = new MavensMateTabView(params)

serverViewUri = 'mavensmate://serverView'
createServerView = (params) ->
  MavensMateServerView ?= require './mavensmate-server-view'
  serverView = new MavensMateServerView(params)


module.exports =

  class MavensMate
    Subscriber.includeInto this

    editorSubscription: null
    autocomplete: null
    providers: []

    panel: null # mavensmate status panel
    localHttpServer: null # express.js server that handles UI interaction
    mavensmateAdapter: null
    serverPort: null

    constructor: ->
      console.log 'New instance of MavensMate plugin...'
      @init()

    # Activates the package, starts the local server, instantiates the views, etc.
    #
    # Returns nothing.
    init: ->
      self = @

      # opens MavensMate UI in an Atom tab
      atom.workspace.registerOpener (uri, params) ->
        createTabView(params) if uri is tabViewUri

      # opens Salesforce.com URL in an Atom tab
      atom.workspace.registerOpener (uri, params) ->
        createServerView(params) if uri is serverViewUri

      atom.workspaceView.mavensMateProjectInitialized ?= false
      console.log 'initing mavensmate.coffee'
      #@promiseTracker = new MavensMatePromiseTracker()

      # instantiate client interface
      @mavensmateAdapter = MavensMateCoreAdapter
      @mavensmateAdapter.initialize()
      atom.mavensmate.adapter = @mavensmateAdapter
      @projectCommands = commands.projectCommands

      # instantiate mavensmate panel, show it
      @panel = MavensMatePanelView

      atom.workspaceView.command "mavensmate:new-project", ->
        params = {}
        params.args = {}
        params.args.operation = 'new-project'
        params.args.url = 'project/new'
        self.mavensmateAdapter.openUI(params)
        # modalView = new MavensMateModalView 'new-project'
        # modalView.appendTo document.body

      # presents a list of projects in a select list
      atom.workspaceView.command "mavensmate:open-project", =>
        # instantiate a mavensmate project list view instance
        @selectList = new MavensMateProjectListView()
        @selectList.toggle()

      atom.project.on 'path-changed', => @onProjectPathChanged()

      @onProjectPathChanged()

      createErrorsView(util.uris.errorsView)
      atom.workspace.registerOpener (uri) ->
        errorsView if uri is util.uris.errorsView

      atom.workspaceView.command 'mavensmate:view-errors', ->
        atom.workspaceView.open(util.uris.errorsView)

    onProjectPathChanged: ->
      if util.isMavensMateProject() and not atom.workspaceView.mavensMateProjectInitialized
        atom.workspaceView.mavensMateProjectInitialized = true
        @initializeProject()
      else
        console.log('not a mavensmate project or already initialized')


    initializeProject: ->
      @panel.toggle()
      self = @

      # hide .overlays from fuzzyfinder (cmd+t) file search
      # fuzzyFinderIgnoredNamesSetting = atom.config.get('fuzzy-finder.ignoredNames')
      # if fuzzyFinderIgnoredNamesSetting?
      #   if fuzzyFinderIgnoredNamesSetting == []
      #     atom.config.pushAtKeyPath("fuzzy-finder.ignoredNames", "**/config/.symbols/*.json")
      #   else if fuzzyFinderIgnoredNamesSetting.length > 0 and '**/config/.symbols/*.json' not in fuzzyFinderIgnoredNamesSetting
      #     atom.config.pushAtKeyPath("fuzzy-finder.ignoredNames", "**/config/.symbols/*.json")
      # else
      #   atom.config.pushAtKeyPath("fuzzy-finder.ignoredNames", "**/config/.symbols/*.json")

      atom.project.errors = {}
      atom.project.checkpointCount = 0
      if atom.project.path
        console.log(atom.project.path)
        self.mavensmateAdapter.client.setProject atom.project.path, (err, response) ->
          console.log('set the project!')
          console.log(err)
          console.log(response)
          logFetcher = new MavensMateLogFetcher(self.mavensmateAdapter.client.getProject())
          return

        # try
        #   data = fs.readFileSync path.join(atom.project.path, 'config','.overlays')
        #   overlays = JSON.parse data
        #   atom.project.checkpointCount = overlays.length
        # catch error
        #   console.log error

        sessionPath = path.join(atom.project.path,'config','.session')

        if fs.existsSync(sessionPath)
          # instantiates atom.project.session with cached session information
          session = util.fileBodyAsString(sessionPath, true)
          atom.project.session = session
          emitter.emit 'mavensmate:session-updated', session

      projectFsWatcher = new FileSystemWatcher(atom.project.path)

      ##COMMANDS TODO: move
      atom.workspaceView.command "mavensmate:toggle-output", =>
        @panel.toggle()

      # deletes file(s) from server
      atom.workspaceView.command "mavensmate:delete-file-from-server", =>
        treeView = util.treeView()
        if treeView.hasFocus() # clicked in sidebar
          filePaths = treeView.selectedPaths()
        else # command palette or right click in editor
          filePaths = [util.activeFile()]
        params =
          args:
            operation: 'delete-metadata'
            pane: atom.workspace.getActivePane()
          payload:
            files: filePaths
        fileString = (filePaths.map (path) -> util.baseName(path)).join(', ')
        answer = atom.confirm
          message: "Are you sure you want to delete #{fileString} from Salesforce?"
          # NB: specs expects the following buton indices, 0: Cancel, 1: Delete
          #     so that we can simulate button clicks properly in the spec
          buttons: ["Cancel", "Delete"]
        if answer == 1 # 1 => Delete
          @mavensmateAdapter.executeCommand(params)
            .then (result) =>
              @mmResponseHandler(params, result)


      # attach commands to workspace based on commands.json
      for commandName, command of @projectCommands
        resolvedName = 'mavensmate:' + commandName

        atom.workspaceView.command resolvedName, (options) =>
          commandName = options.type.split(':').pop()
          command = @projectCommands[commandName]
          if command?
            params =
              args:
                operation: command.operation
                pane: atom.workspace.getActivePane()

            if 'ui' of command
              params.args.ui = command.ui
            if 'view' of command
              params.args.view = command.view
            if 'url' of command
              params.args.url = command.url
            else
              params.args.view = 'modal'

            payload = {}
            if 'payloadFiles' of command
              switch command['payloadFiles']
                when 'active'
                  payload.files = [util.activeFile()]
                when 'selected'
                  payload.files = util.getSelectedFiles()
            if 'payloadClasses' of command
              switch command['payloadClasses']
                when 'activeBaseName'
                  if util.activeFile().indexOf('.cls') >= 0
                    payload.classes = [util.activeFileBaseName().split('.')[0]]
            if 'payloadMetadata' of command
              payload.metadata_type = command.payloadMetadata
            if 'payloadType' of command
              payload.type = command.payloadType
            console.log 'command payload: '
            console.log payload
            if Object.keys(payload).length != 0
              params.payload = payload
            console.log(params.payload)

            if params.args.ui
              self.mavensmateAdapter.openUI(params)
            else
              answer = 0
              if command.confirm?
                answer = atom.confirm
                  message: command.confirm.message
                  detailedMessage: command.confirm.message
                  buttons: command.confirm.buttons
              if answer == 0 # Yes
                self.mavensmateAdapter.executeCommand(params)
                  .then (result) ->
                    self.mmResponseHandler(params, result)



      # places mavensmate 3 dot icon in the status bar
      createStatusEntry = =>
        @mavensmateStatusBar = new MavensMateStatusBarView(@panel)

      if atom.workspaceView.statusBar
        createStatusEntry()
      else
        atom.packages.once 'activated', ->
          createStatusEntry()

      # we rely upon autocomplete plus right now
      if !util.isAutocompletePlusInstalled()
        @installAutocompletePlus()
      else
        @enableAutocomplete()

      # attach MavensMate views/handlers to each present and future editor views
      atom.workspaceView.eachEditorView (editorView) =>
        @handleBufferEvents editorView
        editorView.errorMarkers = new MavensMateErrorMarkers(editorView)
        # TODO: shouldn't we scope this to MavensMate projects only?
        # creates/deletes/displays checkpoints in gutter
        # editorView.checkpointHandler = new MavensMateCheckpointHandler(editorView, @mm, @mmResponseHandler)
        
    installAutocompletePlus: ->
      # cmd = "#{atom.packages.getApmPath()} install autocomplete-plus"
      # exec cmd, @enableAutocomplete

    enableAutocomplete: ->
      atom.packages.activatePackage("autocomplete-plus")
        .then (pkg) =>
          @autocomplete = pkg.mainModule
          @registerProviders()

    registerProviders: ->
      MavensMateCodeAssistProviders = require './mavensmate-code-assist-providers'

      @editorSubscription = atom.workspaceView.eachEditorView (editorView) =>
        if editorView.attached and not editorView.mini
          apexProvider = new MavensMateCodeAssistProviders.ApexProvider(editorView.editor)
          @autocomplete.registerProviderForEditor apexProvider, editorView.editor
          @providers.push apexProvider

          vfTagProvider = new MavensMateCodeAssistProviders.VisualforceTagProvider(editorView.editor)
          @autocomplete.registerProviderForEditor vfTagProvider, editorView.editor
          @providers.push vfTagProvider

          # vfTagContextProvider = new MavensMateCodeAssistProviders.VisualforceTagContextProvider(editorView)
          # @autocomplete.registerProviderForEditorView vfTagContextProvider, editorView
          # @providers.push vfTagContextProvider

          # apexContextProvider = new MavensMateCodeAssistProviders.ApexContextProvider(editorView)
          # @autocomplete.registerProviderForEditorView apexContextProvider, editorView
          # @providers.push apexContextProvider

          # sobjectProvider = new MavensMateCodeAssistProviders.SobjectProvider(editorView)
          # @autocomplete.registerProviderForEditorView sobjectProvider, editorView
          # @providers.push sobjectProvider

    # Public: Deactivate the package and destroy the mavensmate views.
    #
    # Returns nothing.
    destroy: ->
      if @localHttpServer?
        @localHttpServer.destroy()
        delete @localHttpServer
    
      # remove MavensMate items from the status bar
      @mavensmateStatusBar?.destroy()
      @mavensmateStatusBar = null

      # remove the MavensMate panel
      @panel.destroy()
      @panel = null

      #unsubscribe from all listeners
      @unsubscribe()

    mmResponseHandler: (params, result) ->
      tracker.pop(result.promiseId).result
      MavensMateEventEmitter.emit 'mavensmate:promise-completed', result.promiseId
      MavensMateEventEmitter.emit 'mavensmate:panel-notify-finish', params, result, result.promiseId

    handleBufferEvents: (editorView) ->
      self = @
      buffer = editorView.editor.getBuffer()

      if buffer.file? and util.isMetadata(buffer.file.getBaseName())
        @subscribe buffer.on 'saved', ->
          params =
            args:
              operation: 'compile-metadata'
              pane: atom.workspace.getActivePane()
              editor: atom.workspace.getActiveEditor()
              editorView: atom.workspaceView.getActiveView()
              buffer: buffer
            payload:
              files: [buffer.file.path]
          self.mavensmateAdapter.executeCommand(params)
            .then (result) ->
              self.mmResponseHandler(params, result)
