{View} = require 'atom'
_           = require 'underscore-plus'
util        = require '../mavensmate-util'
pluralize   = require 'pluralize'
emitter     = require('../mavensmate-emitter').pubsub

class CommandParser
  
  obj:
    message: null
    indicator: 'warning'
    stackTrace: null
    result: null
    isException: false

  constructor: (@command, @params, @result) ->
    @obj.result = result

  parse: ->
    console.log('parsing!')
    console.log @result
    if @result.result? and not @result.error?
      @result.success = true
      @obj.message = @result.result
      @obj.indicator = if @result.success then 'success' else 'danger'
      @obj.stackTrace = @result.stack
      @obj.isException = @result.stack?
    else if @result.result? and @result.error
      @obj = @getErrorOutput()
    else
      @obj.message = 'Unable to parse the command\'s result. This really should not happen, so please generate a log and create a GitHub issue (please search before creating new issues!)'
      @obj.indicator = 'warning'
      @obj.stackTrace = @result.stack
      @obj.isException = @result.stack?

    return @obj

  getErrorOutput: ->
    output =
      message: @result.result
      indicator: 'danger'
      stackTrace: @result.stack
      isException: @result.stack?

class GetOrgWideTestCoverageParser extends CommandParser

  parse: ->
    @obj.indicator = 'info'
    @obj.message = "Total Apex Unit Test Coverage: #{@result.PercentCovered}%"
    return @obj

class DeleteParser extends CommandParser

  parse: ->
    if @result.result.success
      @obj.indicator = "success"
      if @params.payload.files? and @params.payload.files.length is 1
        @obj.message = 'Deleted ' + util.baseName(@params.payload.files[0])
      else
        @obj.message = "Deleted selected metadata"
      return @obj
    else
      @getErrorOutput @params, @result

class UiParser extends CommandParser

  parse: ->
    if @result.success
      @obj.message = 'UI generated successfully'
      @obj.indicator = 'success'
      return @obj
    else
      return @getErrorOutput @params, @result

class CompileParser extends CommandParser

  parse: ->
    if @result.error?
      @obj.message = @result.error
      @obj.success = false
      return

    filesCompiled = {}
    for filePath in @params.payload.files
      fileNameBase = util.baseName(filePath)
      fileNameWithoutExtension = util.withoutExtension(fileNameBase)
      compiledFile = {}
      compiledFile.filePath = filePath
      compiledFile.fileNameWithoutExtension = fileNameWithoutExtension
      compiledFile.fileNameBase = fileNameBase
      filesCompiled[fileNameWithoutExtension] = compiledFile

      atom.project.errors[filePath] = []

    for filePath, errors of atom.project.errors
      fileNameBase = util.baseName(filePath)
      fileNameWithoutExtension = util.withoutExtension(fileNameBase)

      if not filesCompiled[fileNameWithoutExtension]?
        compiledFile = {}
        compiledFile.filePath = filePath
        compiledFile.fileNameWithoutExtension = fileNameWithoutExtension
        compiledFile.fileNameBase = fileNameBase
        filesCompiled[fileNameWithoutExtension] = compiledFile

    errorsByFilePath = {}

    if _.isArray @result.result
      for compileResult in @result.result
        console.log 'result!'
        console.log compileResult

        if compileResult.State? # tooling
          if compileResult.State is 'Error' and compileResult.ErrorMsg?
            @obj.message = compileResult.ErrorMsg
            @obj.success = false
          else if compileResult.State is 'Failed' and compileResult.CompilerErrors?
            if Object.prototype.toString.call compileResult.CompilerErrors is '[object String]'
              compileResult.CompilerErrors = JSON.parse compileResult.CompilerErrors

            errors = compileResult.CompilerErrors
            message = 'Compile Failed'
            for error in errors
              if filesCompiled[error.name]?
                error.fileName = filesCompiled[error.name].fileNameBase
                error.filePath = filesCompiled[error.name].filePath
              else
                error.fileName = error.name
                error.filePath = error.name
              if error.line?
                errorMessage = "#{error.fileName}: #{error.problem[0]} (Line: #{error.line[0]})"
                error.lineNumber = error.line[0]
              else
                errorMessage = "#{error.fileName}: #{error.problem}"
              message += '<br/>' + errorMessage

              errorsByFilePath[error.filePath] ?= []
              errorsByFilePath[error.filePath].push(error)
            @obj.message = message
            @obj.indicator = 'danger'
          else if compileResult.State is 'Failed' and compileResult.DeployDetails?
            errors = compileResult.DeployDetails.componentFailures
            message = 'Compile Failed'
            for error in errors
              errorName = error.fileName || error.fullName || error.name
              if filesCompiled[errorName]?
                error.fileName = filesCompiled[errorName].fileNameBase
                error.filePath = filesCompiled[errorName].filePath
              else
                error.fileName = errorName
                error.filePath = errorName
              if error.lineNumber
                errorMessage = "#{error.fileName}: #{error.problem} (Line: #{error.lineNumber})"
              else
                errorMessage = "#{error.fileName}: #{error.problem}"
              message += '<br/>' + errorMessage

              errorsByFilePath[error.filePath] ?= []
              errorsByFilePath[error.filePath].push(error)

            @obj.message = message
            @obj.indicator = 'danger'
          else if compileResult.State is 'Completed' and not compileResult.ErrorMsg
            @obj.indicator = 'success'
            @obj.message = 'Success'
          else
            #pass
        else if compileResult.actions?
          # need to diff
          @obj.message = compileResult.body
          @obj.indicator = 'warning'
        # else if
        #   #todo
        for filePath, errors of errorsByFilePath
          fileNameBase = util.baseName(filePath)
          fileNameWithoutExtension = util.withoutExtension(fileNameBase)
          if atom.project.errors[fileNameWithoutExtension]?
            delete atom.project.errors[fileNameWithoutExtension]
          atom.project.errors[filePath] = errors
        if !@obj.message?
          throw new Error 'unable to parse'
    else
      message = ''
      @obj.success = @result.result.success
      if not _.isArray(@result.result.details.componentFailures)
        @result.result.details.componentFailures = [@result.result.details.componentFailures]

      if not @obj.success
        @obj.indicator = 'danger'
        message = 'Compile Failed'
        for failure in @result.result.details.componentFailures
          message += '<br/>- ' + failure.fullName + ', ' + failure.problem + '(Line: ' + failure.lineNumber + ')'
      else
        @obj.indicator = 'success'
        message = 'Success'
      @obj.message = message
    
    return @obj

class CleanProjectParser extends CommandParser

  parse: ->
    atom.project.errors = {}
    super

class RefreshMetadataParser extends CommandParser

  parse: ->
    filesRefreshed = (util.baseName(filePath) for filePath in @params.payload.files ? [])
    for refreshedFile in filesRefreshed
      atom.project.errors[refreshedFile] = []
    super

class CompileProjectParser extends CommandParser

  parse: ->
    if @result.success?
      atom.project.errors = {}
      @obj.success = @result.success
      if @result.success
        @obj.message = "Success"
        @obj.indicator = 'success'
        emitter.emit 'mavensmate:compile-success-buffer-notify', @params
      else
        if @result.Messages?
          errors = @result.Messages
          @obj.indicator = 'danger'

          message = 'Compile Project Failed'
          for error in errors
            error.returnedPath = error.fileName
            error.fileName = util.baseName(error.returnedPath)
            treePath = './' + error.returnedPath.replace('unpackaged', 'src')
            error.filePath = atom.project.resolve(treePath)
            if error.lineNumber? and error.columnNumber?
              errorMessage = "#{error.fileName}: #{error.problem} (Line: #{error.lineNumber}, Column: #{error.columnNumber})"
            else
              lineColumnRegEx = /line\s(\d+)\scolumn\s(\d+)/
              match = lineColumnRegEx.exec(error.problem)
              if match? and match.length > 2
                error.lineNumber = match[1]
                error.columnNumber = match[2]
              errorMessage = "#{error.fileName}: #{error.problem}"
            message += '<br/>' + errorMessage

            atom.project.errors[error.filePath] ?= []
            atom.project.errors[error.filePath].push(error)
        else
          message = 'Compile Project Failed To Compile'
          message += '<br/>' + @result.body
          @obj.stackTrace = @result.stack_trace
          @obj.isException = @result.stack_trace?

        @obj.message = message
        @obj.indicator = 'danger'
    return @obj

class RunTestsParser extends CommandParser

  class TestResultView extends View
    
    @content: (params) ->
      @div =>
        @span params.message
        @div outlet: 'results', class: 'mavensmate-test-result'
          
    addTestResults: (result) ->
      console.log 'adding result for: '
      console.log result
      html = ''
      
      passCounter = 0
      failedCounter = 0
      
      for test in result.results
        if test.Outcome == "Fail"
          failedCounter++
        else
          passCounter++

        
        clsName = 'Pass'
        if failedCounter > 0
          clsName = 'Fail'

      html += '<p class="class-name">'+result.ApexClass.Name
      html += ' | <span class="'+clsName+'">'+result.ExtendedStatus+' '+pluralize('test', result.results.length)+ ' passed</span>'
      html += '</p>'
      
      for test in result.results
        html += '<p class="method-name"><span class="result '+test.Outcome+'">['+test.Outcome+']</span> '+test.MethodName+'</p>'
        if test.Outcome == 'Fail'
          html += '<p class="stack">'
          html += test.Message
          html += '<br/>'
          html += test.StackTrace
          html += '</p>'
      
      console.log html

      @results.append html

  commandAliases: ['test_async']

  parse: ->
    passCounter = 0
    failedCounter = 0

    message = 'Results:\n'
      
    # console.log parserViews
    testResultView = new TestResultView(message:'> Results:')
    testKey = Object.keys(@result.result.testResults)[0]
    testResultsForThisClass = @result.result.testResults[testKey]
    testResultView.addTestResults(testResultsForThisClass)
    console.log testResultView
    # # console.log markdown
    # htmlMessage = converter.makeHtml(markdown)
    @obj.indicator = 'info'
    # @obj.message = message + htmlMessage
    @obj.message = testResultView

    # totalTests = passCounter + failedCounter
    # if failedCounter == 0
    #   @obj.message = "Run tests. #{passCounter} tests " + (if passCounter > 1 then "s " else " ") + "passed."
    #   @obj.indicator = 'success'
    # else
    #   @obj.indicator = 'danger'
    #   @obj.isException = true

    return @obj

class LoggingParser extends CommandParser

  parse: ->
    if @result.error?
      @obj.indicator = 'danger'
      @obj.isException = true
      @obj.stackTrace = @result.stack
    else
      @obj.indicator = 'info'

    @obj.message = @result.result
    return @obj

class OpenSfdcUrlParser extends CommandParser

  parse: ->
    if @result.success is true
      me = @
      setTimeout(->
        util.openUrlInAtom(me.result)
      , 100)
    super
      
parsers = {
  CommandParser: CommandParser,
  DeleteParser: DeleteParser,
  UiParser: UiParser,
  CompileMetadataParser: CompileParser,
  CompileProjectParser: CompileProjectParser,
  RunTestsParser: RunTestsParser,
  TestAsyncParser: RunTestsParser,
  StartLoggingParser: LoggingParser,
  StopLoggingParser: LoggingParser,
  GetOrgWideTestCoverageParser: GetOrgWideTestCoverageParser,
  RefreshMetadataParser: RefreshMetadataParser,
  CleanProjectParser: CleanProjectParser,
  OpenSfdcUrlParser: OpenSfdcUrlParser
}

getCommandParser = (command, params) ->
  
  if params.args? and params.args.ui
    return UiParser
  else
    parserClassName = _.camelize(command)
    parserClassName = _.capitalize(parserClassName)
    parserClassName += 'Parser'
    console.log parserClassName
    if parserClassName not of parsers
      return CommandParser
    else
      return parsers[parserClassName]

module.exports =
  
  parse: (command, params, result) ->
    Parser = getCommandParser(command, params)
    console.log 'parser is: '
    console.log Parser
    parser = new Parser(command, params, result)
    return parser.parse()
































