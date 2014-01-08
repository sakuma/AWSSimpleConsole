AWSSC = AWSSC ? {}
window.AWSSC = AWSSC

$.wait = (duration) ->
  dfd = $.Deferred()
  setTimeout(dfd.resolve, duration)
  return dfd

AWSSC.EC2 = (opts) ->
  self = {}
  self.opts = opts

  canvas = $("##{opts.canvas}")
  panelVC_list = []
  hide_stopped = false

  self.show_ec2_instances = (regions) ->
    regions ?= region_list
    for region in regions
      $.get("/api/ec2/?region=#{region}").done (response) ->
        if response.ec2_list && response.ec2_list.length > 0
          rc = $("<div>").append($("<h1>").html(response.region))
          canvas.append(rc)
          panelVC = AWSSC.PanelViewController(canvas: rc)
          panelVC.add_models(response.ec2_list, response.region)
          panelVC_list.push(panelVC)

  $("##{opts.reload}").on "click", ->
    for panelVC in panelVC_list
      panelVC.reload_all()

  $("##{opts.toggle_hide_stop}").on "click", ->
    hide_stopped = !hide_stopped
    for panelVC in panelVC_list
      panelVC.toggle_hide_stop(hide_stopped)

  return self

AWSSC.EC2Model = (data) ->
  self = {}
  self.data = data
  self.region = data.region
  polling_sec = 10000

  self.is_running = -> self.data.status == "running"

  self.is_stopped = -> self.data.status == "stopped"

  self.can_start_stop = ->
    self.data.tags['APIStartStop'] == 'YES'

  self.update = ->
    $.get("/api/ec2/#{self.data.ec2_id}?region=#{self.region}")
    .done (response) ->
        self.data = response.ec2
    .always (response) ->
        console.log response


  check_state = (dfd, ok_func, ng_func) ->
    $.wait(polling_sec).done ->
      self.update().done ->
        if ok_func()
          dfd.resolve()
        else if ng_func()
          dfd.fail()
        else
          dfd.notify()
          check_state()

  self.start_instance = ->
    dfd = $.Deferred()
    $.post("/api/ec2/#{self.data.ec2_id}/start?region=#{self.region}")
    .always (response) ->
        console.log(response)
    .fail (response) ->
        dfd.reject(response)
    .done (response) ->
        check_state(dfd, self.is_running, self.is_stopped)
    dfd.promise()


  self.stop_instance = ->
    dfd = $.Deferred()
    $.post("/api/ec2/#{self.data.ec2_id}/stop?region=#{self.region}")
    .always (response) ->
      console.log response
    .fail (response) ->
        dfd.reject(response)
    .done (response) ->
        check_state(dfd, self.is_stopped, self.is_running)
    dfd.promise()

  return self

AWSSC.PanelViewController = (opts) ->
  self = {}
  self.opts = opts
  canvas = opts.canvas
  panel_list = []

  self.add_models = (ec2_list, region) ->
    for ec2 in ec2_list
      ec2.region = region
      ec2model = AWSSC.EC2Model(ec2)
      self.add(ec2model)

  self.reload_all = ->
    for panel in panel_list
      panel.reload()

  self.toggle_hide_stop = (hide_stopped) ->
    for panel in panel_list
      panel.toggle_hide_stop(hide_stopped)


  self.add = (ec2model) ->
    panel = AWSSC.PanelView(ec2model)
    panel_list.push(panel)
    canvas.append(panel.content)
    panel.update_view()


  return self

AWSSC.PanelView = (model) ->
  self = {}
  self.model = model
  self.content = $('<div class="ec2-panel-item">')
  .append($('<div class="ec2-panel-item-name">'))
  .append((update_btn = $('<button type="button" class="btn btn-small">UPDATE</button>') ))
  .append($('<div class="ec2-panel-item-type">'))
  .append($('<div class="ec2-panel-item-launch-time">'))
  .append($('<div class="ec2-panel-item-status">'))
  .append((start_stop_btn = $('<button type="button" class="btn btn-default ec2-start-stop">')))
  .append($('<div class="ec2-panel-item-cost">').html("-"))

  confirm_action = ->
    a = Math.floor(Math.random() * 100)
    b = Math.floor(Math.random() * 100)
    c = prompt("#{a} + #{b} == ??")
    ret = (a + b == Math.floor(c))
    console.log ret
    ret

  start_stop_btn.on "click", ->
    if confirm_action()
      if model.is_running()
        dfd = model.stop_instance()
      else
        dfd = model.start_instance()
      dfd.progress ->
        self.update_view()
      .always ->
        self.update_view()

  update_btn.on "click", ->
    self.model.update().done ->
      self.update_view()


  self.update_view = ->
    data = self.model.data
    launch_time = new Date(data.launch_time)
    now = new Date()
    hours = Math.floor((now - launch_time)/1000/3600)
    cost_per_hour = Math.floor(cost_table[data.instance_type] * region_rate["ap-southeast-1"] * 10000) / 10000
    cost = Math.floor(cost_per_hour * hours)
    self.content.find(".ec2-panel-item-name").html(data.tags.Name)
    self.content.find(".ec2-panel-item-type").html(data.instance_type).addClass(data.instance_type.replace(".", ""))
    self.content.find(".ec2-panel-item-launch-time").html(launch_time.toLocaleString())
    self.content.find(".ec2-panel-item-status").html(data.status).addClass(data.status)
    if model.is_running()
      self.content.find(".ec2-panel-item-cost").html("#{hours}H × #{cost_per_hour}$ ≒ #{cost}$")
      self.content.find(".ec2-start-stop").html("STOP")
    else
      self.content.find(".ec2-start-stop").html("START")
    unless model.can_start_stop()
      self.content.find(".ec2-start-stop").hide()





  self.reload = ->
    self.model.update().done (response) ->
      self.update_view()

  self.toggle_hide_stop = (hide_stopped) ->
    if self.model.data.status == 'stopped' && hide_stopped
      self.content.hide()
    if !hide_stopped
      self.content.show()




  return self

cost_table =   # virginia, US doller per hour
  "m3.xlarge": 0.45
  "m3.2xlarge": 0.9
  "m1.small": 0.06
  "m1.medium": 0.12
  "m1.large": 0.24
  "m1.xlarge": 0.48
  "c3.large": 0.15
  "c3.xlarge": 0.3
  "c3.2xlarge": 0.6
  "c3.4xlarge": 1.2
  "c3.8xlarge": 2.4
  "c1.medium": 0.145
  "c1.xlarge": 0.58
  "cc2.8xlarge": 2.4
  "g2.2xlarge": 0.65
  "cg1.4xlarge": 2.1
  "m2.xlarge": 0.41
  "m2.2xlarge": 0.82
  "m2.4xlarge": 1.64
  "cr1.8xlarge": 3.5
  "i2.xlarge": 0.853
  "i2.2xlarge": 1.705
  "i2.4xlarge": 3.41
  "i2.8xlarge": 6.82
  "hs1.8xlarge": 4.6
  "hi1.4xlarge": 3.1
  "t1.micro": 0.02

region_rate =
  "ap-southeast-1": 8/6.0

region_list = [
  "us-east-1"
  "us-west-2"
  "us-west-1"
  "eu-west-1"
  "ap-southeast-1"
  "ap-southeast-2"
  "ap-northeast-1"
  "sa-east-1"
]