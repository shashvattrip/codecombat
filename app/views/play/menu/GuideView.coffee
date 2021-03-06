CocoView = require 'views/core/CocoView'
template = require 'templates/play/menu/guide-view'
Article = require 'models/Article'
utils = require 'core/utils'
LevelOptions = require 'lib/LevelOptions'

# let's implement this once we have the docs database schema set up

module.exports = class LevelGuideView extends CocoView
  template: template
  id: 'guide-view'
  className: 'tab-pane'
  helpVideoHeight: '295'
  helpVideoWidth: '471'

  constructor: (options) ->
    @levelID = options.level.get('slug')
    @helpVideos = LevelOptions[@levelID]?.helpVideos ? []
    @trackedHelpVideoStart = @trackedHelpVideoFinish = false
    
    # A/B Testing video tutorial styles
    @helpVideosIndex = me.getVideoTutorialStylesIndex(@helpVideos.length)
    
    @firstOnly = options.firstOnly
    @docs = options?.docs ? options.level.get('documentation') ? {}
    general = @docs.generalArticles or []
    specific = @docs.specificArticles or []

    articles = options.supermodel.getModels(Article)
    articleMap = {}
    articleMap[article.get('original')] = article for article in articles
    general = (articleMap[ref.original] for ref in general)
    general = (article.attributes for article in general when article)

    @docs = specific.concat(general)
    @docs = $.extend(true, [], @docs)
    @docs = [@docs[0]] if @firstOnly and @docs[0]
    doc.html = marked(utils.i18n doc, 'body') for doc in @docs
    doc.name = (utils.i18n doc, 'name') for doc in @docs
    doc.slug = _.string.slugify(doc.name) for doc in @docs
    super()

  destroy: ->
    if @vimeoListenerAttached
      if window.addEventListener
        window.removeEventListener('message', @onMessageReceived, false)
      else
        window.detachEvent('onmessage', @onMessageReceived, false)
    if window.onYouTubeIframeAPIReady
      window.onYouTubeIframeAPIReady = null
    super()

  getRenderData: ->
    c = super()
    c.docs = @docs
    c.showVideo = @helpVideos.length > 0
    c

  afterRender: ->
    super()
    if @docs.length is 1 and @helpVideos.length > 0
      @setupVideoPlayer()
    else
      # incredible hackiness. Getting bootstrap tabs to work shouldn't be this complex
      @$el.find('.nav-tabs li:first').addClass('active')
      @$el.find('.tab-content .tab-pane:first').addClass('active')
      @$el.find('.nav-tabs a').click(@clickTab)
    @playSound 'guide-open'

  clickTab: (e) =>
    @$el.find('li.active').removeClass('active')
    @playSound 'guide-tab-switch'

  afterInsert: ->
    super()
    Backbone.Mediator.publish 'level:docs-shown', {}

  onHidden: ->
    createjs?.Sound?.setVolume?(@volume ? 1.0)
    Backbone.Mediator.publish 'level:docs-hidden', {}

  onShown: ->
    # TODO: Disable sound only when video is playing?
    @volume ?= me.get('volume') ? 1.0
    createjs?.Sound?.setVolume(0.0)

  onStartHelpVideo: ->
    unless @trackedHelpVideoStart
      window.tracker?.trackEvent 'Start help video', level: @levelID, style: @helpVideos[@helpVideosIndex].style
      @trackedHelpVideoStart = true
  
  onFinishHelpVideo: ->
    unless @trackedHelpVideoFinish
      window.tracker?.trackEvent 'Finish help video', level: @levelID, style: @helpVideos[@helpVideosIndex].style
      @trackedHelpVideoFinish = true

  setupVideoPlayer: () ->
    return unless @helpVideos.length > 0
    
    # TODO: run A/B test for different video styles

    helpVideoURL = @helpVideos[@helpVideosIndex].URL
    if helpVideoURL.toLowerCase().indexOf('youtube') >= 0
      @setupYouTubeVideoPlayer helpVideoURL
    else if helpVideoURL.toLowerCase().indexOf('vimeo') >= 0
      @setupVimeoVideoPlayer helpVideoURL

  setupYouTubeVideoPlayer: (helpVideoURL) ->
    # Setup YouTube iframe player
    # https://developers.google.com/youtube/iframe_api_reference
    # TODO: Can't load a YouTube video twice in one level
    # TODO: window.onYouTubeIframeAPIReady is only called once
    # TODO: Consider ripping out YouTube support and migrating all videos to Vimeo

    onPlayerStateChange = (e) =>
      if e.data is 1
        @onStartHelpVideo()
      else if e.data is 0
        @onFinishHelpVideo()

    createPlayer = =>
      new YT.Player 'help-video-player', {
        height: @helpVideoHeight,
        width: @helpVideoWidth,
        videoId: videoID,
        events: {
          'onStateChange': onPlayerStateChange
        }
      }

    if matchVideoID = helpVideoURL.match /www\.youtube\.com\/embed\/(bHaeKdMPZrA)/
      videoID = matchVideoID[1]
    else
      console.warn "Unable to read video ID from help video."
      # TODO: Default to dungeons-of-kithgard?
      videoID = 'bHaeKdMPZrA'
    
    # Add method that will be called by YouTube iframe player when ready
    window.onYouTubeIframeAPIReady = =>
      createPlayer()
    
    # Add YouTube video player iframe script if necessary
    if YT?.Player?
      createPlayer()
    else
      tag = document.createElement('script')
      tag.src = "https://www.youtube.com/iframe_api"
      @$el.find('#help-video-heading').after(tag)

  setupVimeoVideoPlayer: (helpVideoURL) ->
    # Setup Vimeo player
    # https://developer.vimeo.com/player/js-api#universal-with-postmessage

    # Create Vimeo iframe player
    tag = document.createElement('iframe')
    tag.id = 'help-video-player'
    tag.src = helpVideoURL + "?api=1&badge=0&byline=0&portrait=0&title=0"
    tag.height = @helpVideoHeight
    tag.width = @helpVideoWidth
    tag.frameborder = '0'
    @$el.find('#help-video-player').replaceWith(tag)

    @onMessageReceived = (e) =>
      data = JSON.parse(e.data)
      if data.event is 'ready'
        # Vimeo player is ready, can now hook up other events
        # https://developer.vimeo.com/player/js-api#events
        player = $('#help-video-player')[0]
        helpVideoURL = 'http:' + helpVideoURL unless helpVideoURL.indexOf('http') is 0
        player.contentWindow.postMessage JSON.stringify(method: 'addEventListener', value: 'play'), helpVideoURL
        player.contentWindow.postMessage JSON.stringify(method: 'addEventListener', value: 'finish'), helpVideoURL
      else if data.event is 'play'
        @onStartHelpVideo?()
      else if data.event is 'finish'
        @onFinishHelpVideo?()

    # Listen for Vimeo player 'ready'
    if window.addEventListener
      window.addEventListener('message', @onMessageReceived, false)
    else
      window.attachEvent('onmessage', @onMessageReceived, false)
    @vimeoListenerAttached = true
