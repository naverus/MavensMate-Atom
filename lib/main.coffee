MavensMate = require './mavensmate'

module.exports =

  configDefaults:
    mm_location: 'mm/mm.py'
    mm_compile_on_save : true
    mm_api_version : '30.0'
    mm_log_location : ''
    mm_python_location : '/usr/bin/python'
    mm_workspace : ['/one/cool/workspace', '/one/not-so-cool/workspace']
    mm_open_project_on_create : true
    mm_log_level : 'DEBUG'
    mm_apex_file_extensions: [".page", ".component", ".cls", ".object", ".trigger", ".layout", ".resource", ".remoteSite", ".labels", ".app", ".dashboard", ".permissionset", ".workflow", ".email", ".profile", ".scf", ".queue", ".reportType", ".report", ".weblink", ".tab", ".letter", ".role", ".homePageComponent", ".homePageLayout", ".objectTranslation", ".flow", ".datacategorygroup", ".snapshot", ".site", ".sharingRules", ".settings", ".callCenter", ".community", ".authProvider", ".customApplicationComponent", ".quickAction", ".approvalProcess", ".html" ]

  # todo: should we initiate the app per editorview?
  # right now, this activates MavensMate once per Atom window
  # i think we want to keep each MavensMate() instance tied to a project, but not 100% sure how to approach that
  activate: =>
    console.log 'activating mavensmate'
    @mavensmate = new MavensMate()

  deactivate: =>
    console.log 'deactivating mavensmate'
    delete @mavensmate
