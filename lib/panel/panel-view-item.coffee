{$, View}             = require 'atom'
{Subscriber,Emitter}  = require 'emissary'
emitter               = require('../mavensmate-emitter').pubsub
util                  = require '../mavensmate-util'
moment                = require 'moment'
parseCommand          = require('./parsers').parse
PanelViewItemResponse = require './panel-view-item-response'

module.exports =
  # represents a single operation/command within the panel
  class MavensMatePanelViewItem extends View

    constructor: (command, params) ->
      super
      @closePanelOnFinish = true
      @command = command
      @running = true

      # set panel font-size to that of the editor
      fontSize = jQuery("div.editor-contents").css('font-size')
      @terminal.context.style.fontSize = fontSize
      
      # get the message
      message = @.panelCommandMessage params, util.isUiCommand params

      # scope this panel by the promiseId
      @promiseId = params.promiseId
      @item.attr 'id', @promiseId

      # write the message to the terminal
      @terminal.html message
      
    # Internal: Initialize mavensmate output view DOM contents.
    @content: ->
      @div class: 'panel-item',  =>
        @div outlet: 'item', =>
          @div class: 'container-fluid', =>
            @div class: 'row', =>
              @div class: 'col-md-12', =>
                @div =>
                  @pre class: 'terminal active', outlet: 'terminal'

    initialize: ->

    # updates terminal view with result of command
    update: (panel, params, result) ->
      console.log 'updating panel item as a result of command ====>'
      console.log params
      console.log result
      me = @      
      if @command not in util.panelExemptCommands() and not params.skipPanel
        panelOutput = parseCommand(@command, params, result)

        if panelOutput.indicator != 'success'
          me.closePanelOnFinish = false

        # update progress bar depending on outcome of command
        me.terminal.removeClass 'active'
        me.terminal.addClass panelOutput.indicator

        # update terminal
        itemResponse = new PanelViewItemResponse(id: @promiseId, message: panelOutput.message, result: result)
        me.terminal.append itemResponse
        # me.terminal.append '<br/>> '+ '<span id="message-'+@promiseId+'">'+panelOutput.message+'</span>'
        me.running = false
      return

    # returns the command message to be displayed in the panel
    # todo: refactor to something like parsers.coffee
    panelCommandMessage: (params, isUi=false) ->
      # console.log params
      
      switch @command
        when 'new-project'
          msg =  'Creating new project'
        when 'compile-project'
          msg = 'Compiling project'
        when 'index-metadata'
          msg = 'Indexing metadata'
        when 'compile-metadata'
          if params.payload.files? and params.payload.files.length is 1
            msg = 'Compiling '+params.payload.files[0].split(/[\\/]/).pop() # extract base name
          else
            msg = 'Compiling selected metadata'
        when 'delete-metadata'
          if params.payload.files? and params.payload.files.length is 1
            msg = 'Deleting ' + params.payload.files[0].split(/[\\/]/).pop() # extract base name
          else
            msg = 'Deleting selected metadata'
        when 'refresh-metadata'
          if params.payload.files? and params.payload.files.length is 1
            msg = 'Refreshing ' + params.payload.files[0].split(/[\\/]/).pop() # extract base name
          else
            msg = 'Refreshing selected metadata'
        when 'clean-project'
          msg = 'Cleaning project'
        when 'run-tests'
          msg = 'Running Apex unit test(s)'
        when 'start-logging'
          msg = 'Creating trace flags for user ids in config/.debug'
        when 'stop-logging'
          msg = 'Deleting trace flags you have created for user ids in config/.debug'
        when 'index-apex'
          msg = 'Indexing Apex symbols for this project'
        else
          msg = 'mm ' + @command
      console.log msg
      header = '['+moment().format('MMMM Do YYYY, h:mm:ss a')+']<br/>'
      return header + '> ' + msg