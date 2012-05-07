bubblesChartWidth = $(document).width()
bubblesChartHeight = $(document).height()*0.9 - 50


inboundColor = "#f98a8b"
outboundColor = "#9292ff"

svg = d3.select("body")
  .append("svg")
    .attr("width", bubblesChartWidth)
    .attr("height", bubblesChartHeight)
    .attr("class", "bubble")


conf = 
  flowOriginAttr: 'donor'
  flowDestAttr: 'recipient'
  nodeIdAttr: 'code'
  nodeLabelAttr: 'name'
  latAttr: 'Lat'
  lonAttr: 'Lon'
  flowMagnAttrs:
    aid:
      attrs: [1947..2011]
      explain: 'In #attr# there were #magnitude# ... from #origin# in #dest#'

state = null




fmt = d3.format(",.0f")
magnitudeFormat = (d) ->
  if (d >= 1e6)
    "$#{fmt(d / 1e6)} million"
  else
    "$#{fmt(d)}" 

shortMagnitudeFormat = (d) -> magnitudeFormat(d).replace(" million", "M")

bubbleTooltip = (d) ->
  "<b>#{d.name}</b>" + 
  #" in <b>#{state.selMagnAttr()}</b>" +
  (if d.outbound > 0 then "<br>donated #{magnitudeFormat(d.outbound)}" else "") +
  (if d.inbound > 0 then "<br>received #{magnitudeFormat(d.inbound)}" else "")


flowTooltip = (d) ->
  recipient = d.target.data[conf.nodeLabelAttr]
  donor = d.source.data[conf.nodeLabelAttr]

  "<b>#{recipient}</b> received<br>"+
  "<b>#{magnitudeFormat(d.data[state.selMagnAttr()])}</b> "+
  (if donor.length > 20 then "<span class=sm>from <b>#{donor}</b></span>" else "from <b>#{donor}</b>") +
  "  in #{state.selMagnAttr()} <br>"+
  "<div id=sparkline></div>"



mapProj = winkelTripel()
mapProjPath = d3.geo.path().projection(mapProj)


createTimeSeries = (parent, data) ->
  margin = {top: 15, right: 3, bottom: 14, left: 40}
  w = 200 - margin.left - margin.right
  h = 100 - margin.top - margin.bottom

  dates = data.map (d) -> d.date
  maxVal = d3.max(d3.values(data.map (d) -> d.value))
  x = d3.time.scale().domain([d3.min(dates), d3.max(dates)]).range([0, w])          
  y = d3.scale.linear().domain([0, maxVal]).range([h, 0])

  line = d3.svg.line()
    .x((d) -> x(d.date))
    .y((d) -> y(d.value))

  xAxis = d3.svg.axis()
    .scale(x)
    .ticks(4)
    .orient("bottom")
    .tickSize(3, 0, 0)

  yAxis = d3.svg.axis()
    .ticks(3)
    .scale(y)
    .orient("left")
    .tickFormat(shortMagnitudeFormat)
    .tickSize(-w, 0, 0)

  tseries = parent
    .append("svg")
      .datum(data)
      .attr("width", w + margin.left + margin.right)
      .attr("height", h + margin.top + margin.bottom)
    .append("g")
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")")

  tseries.append("rect")
    .attr("class", "background")
    .attr("x", 0)
    .attr("y", 0)
    .attr("width", w)
    .attr("height", h)

  tseries.append("g")
    .attr("class", "y axis")
    .call(yAxis)

  tseries.append("g")
    .attr("class", "x axis")
    .attr("transform", "translate(0," + h + ")")
    .call(xAxis)


  tseries
    .append("path")
    .attr("class", "line")
    .attr("d", line)

  tseries.append("circle")
    .attr("class","selAttrValue")
    .attr("cx", x(data[state.selAttrIndex].date))
    .attr("cy", y(data[state.selAttrIndex].value))
    .attr("r", 2)



projectNode = (node) ->  
  lon = node[conf.lonAttr]
  lat = node[conf.latAttr]
  if (isNumber(lon) and isNumber(lat))
    mapProj([lon, lat])
  else
    undefined


force = d3.layout.force()
    .charge(0)
    .gravity(0)
    .size([bubblesChartWidth, bubblesChartHeight])

idToNode = {}


loadData()
  .csv('nodes', "#{dynamicDataPath}aiddata-nodes.csv")
  .csv('flows', "#{dynamicDataPath}aiddata-totals-d-r-y.csv")
  #.csv('originTotals', "#{dynamicDataPath}aiddata-donor-totals.csv")
  #.csv('destTotals', "#{dynamicDataPath}aiddata-recipient-totals.csv")
  .json('map', "data/world-countries.json")
  .csv('countries', "data/aiddata-countries.csv")
  .onload (data) ->


    svg.append("rect")
      .attr("x", 0)
      .attr("y", 0)
      .attr("width", bubblesChartWidth)
      .attr("height", bubblesChartHeight)
      .attr("fill", "white")
      .on 'click', (d) -> clearNodeSelection()


    fitProjection(mapProj, data.map, [[0,20],[bubblesChartWidth, bubblesChartHeight*0.8]], true)

    state = initFlowData(conf)
    state.selMagnAttrGrp = "aid"
    state.selAttrIndex = state.magnAttrs().length - 1



    provideNodesWithTotals(data, conf)
    provideCountryNodesWithCoords(
      data.nodes, { code: conf.nodeIdAttr, lat: conf.latAttr, lon: conf.lonAttr},
      data.countries, { code: "Code", lat: "Lat", lon: "Lon" }
    )


    state.totalsMax = calcMaxTotalMagnitudes(data, conf)


    maxTotalMagnitudes = state.totalsMax[state.selMagnAttrGrp]
    maxTotalMagnitude = Math.max(d3.max(maxTotalMagnitudes.inbound), d3.max(maxTotalMagnitudes.outbound))

    rscale = d3.scale.sqrt()
      .range([0, Math.min(bubblesChartWidth/15, bubblesChartHeight/7)])
      .domain([0, maxTotalMagnitude])
    maxr = rscale.range()[1]

    fwscale = d3.scale.sqrt() #.linear()
      .range([0,  maxr *2])
      .domain([0, maxTotalMagnitude])

    hasFlows = (node, flowDirection) -> 
      totals = node.totals?[state.selMagnAttrGrp]?[flowDirection]
      (if totals? then d3.max(totals) > 0 else 0)

    nodesWithFlows = data.nodes.filter(
      (node) -> hasFlows(node, "inbound") or hasFlows(node, "outbound")
    )

    #nodesWithLocation = nodesWithFlows.filter (node) -> projectNode(node)?

    #nodesWithoutLocationX = 0

    nodes = nodesWithFlows.map (d) ->
      xy = projectNode(d)

      maxin = d3.max(d.totals[state.selMagnAttrGrp].inbound ? [0])
      maxout = d3.max(d.totals[state.selMagnAttrGrp].outbound ? [0])

      idToNode[d[conf.nodeIdAttr]] =
        data : d
        max : Math.max(maxin, maxout)
        name: d[conf.nodeLabelAttr] 
        code: d[conf.nodeIdAttr]
        x: xy?[0]
        y: xy?[1]
        gravity: {x: xy?[0], y: xy?[1]}

    updateNodeSizes = ->
      for n in nodes
        d = n.data
        n.inbound = d.totals[state.selMagnAttrGrp].inbound?[state.selAttrIndex] ? 0
        n.outbound = d.totals[state.selMagnAttrGrp].outbound?[state.selAttrIndex] ? 0
        n.rin = rscale(n.inbound)
        n.rout = rscale(n.outbound)
        n.r = Math.max(n.rin, n.rout)
        n.maxr = rscale(n.max)


    updateNodeSizes()

    placeNodesWithoutCoords = (nodes) ->
      totalw = 0
      for n in nodes
        if not n.x? or not n.y? then totalw += 2 * n.maxr/2
      x = 0
      for n in nodes
        if not n.x? or not n.y?
          n.x = x + n.maxr/2 + (bubblesChartWidth - totalw)/2
          n.y = bubblesChartHeight - 75
          n.gravity = {x: n.x, y: n.y}
          x += 2 * n.maxr/2

    placeNodesWithoutCoords(nodes)


    nodeById = (id) ->
      #if not idToNode[id]? then console.log "Warning: No node by id '#{id}' found"
      idToNode[id]

    links = []
    data.flows.forEach (f) ->
      src = nodeById(f[conf.flowOriginAttr])
      target = nodeById(f[conf.flowDestAttr])
      if src? and target?
        link = 
          source: src
          target: target
          data: f 
        
        (src.outlinks ?= []).push link
        (target.inlinks ?= []).push link
        links.push link

    v = (d) -> +d.data[state.selMagnAttr()]

    force
        .nodes(nodes)
        #.links(links)
        #.linkStrength(0)
        #.linkDistance(1)
        #.start()
        .on("tick", (e) -> 
          
          k = e.alpha
          kg = k * .02


          nodes.forEach((a, i) ->
            # Apply gravity forces
            a.x += (a.gravity.x - a.x) * kg
            a.y += (a.gravity.y - a.y) * kg
            nodes.slice(i + 1).forEach((b) -> 
              # Check for collisions.
              dx = a.x - b.x
              dy = a.y - b.y
              l = Math.sqrt(dx * dx + dy * dy)
              d = a.r + b.r
              if (l < d)
                l = (l - d) / l * k
                dx *= l
                dy *= l
                a.x -= dx
                a.y -= dy
                b.x += dx
                b.y += dy
            )
          )

          svg.selectAll("g.bubble")
            .attr("transform", (d) -> "translate(#{d.x},#{d.y})")

          flows.selectAll("line")
            .attr("x1", (d) -> d.source.x )
            .attr("y1", (d) -> d.source.y )
            .attr("x2", (d) -> d.target.x )
            .attr("y2", (d) -> d.target.y )
    )


    svg.append("g")
      .attr("class", "map")
      .selectAll('path')
        .data(data.map.features)
      .enter().append('path')
        .attr('d', mapProjPath)
        .attr("fill", "#f0f0f0")
        .on 'click', (d) -> clearNodeSelection()

    flows = svg.append("g")
      .attr("class", "flows")



    selectedNode = null

    showFlowsOf = (bbl) ->
      d = d3.select(bbl).data()?[0]
      ###
      ffwscale = d3.scale.linear()
        .range([0, rscale.range()[1]/2])
        .domain([0, Math.max(d3.max(max.inbound), d3.max(max.outbound))])
      ###

      if (d.outlinks?)
        flows.selectAll("line.out")
            .data(d.outlinks) #.filter (d) -> v(d) > 0)
          .enter().append("svg:line")
            .attr("class", "out")
            #.attr("stroke", outboundColor)
            #.attr("opacity", 0.5)


      if (d.inlinks?)
        flows.selectAll("line.in")
            .data(d.inlinks) #.filter (d) -> v(d) > 0)
          .enter().append("svg:line")
            .attr("class", "in")
            #.attr("stroke", inboundColor)
            #.attr("opacity",0.5)

      flows.selectAll("line")
        .attr("x1", (d) -> d.source.x )
        .attr("y1", (d) -> d.source.y )
        .attr("x2", (d) -> d.target.x )
        .attr("y2", (d) -> d.target.y )
        .attr("stroke-width", (d) -> fwscale(v(d)))
        .attr("visibility", (d) -> if v(d) > 0 then "visible" else "hidden")
        .on "mouseover", (d) ->
          if this.parentNode?
            this.parentNode.appendChild(this)

          $(this).tipsy("show")


          data = state.magnAttrs().map (attr) -> 
              date: new Date(""+attr)
              value: +d.data[attr]


          createTimeSeries(d3.select("#sparkline"), data)

          $(tipsy.$tip)
              .css('top', event.pageY-($(tipsy.$tip).outerHeight()/2))
              .css('left', event.pageX + 10)


        .on "mouseout", (d) ->
          $(this).tipsy("hide")

        ###
        .on "mouseover", (d) ->
          d3.select(this)
            .transition()
            .duration(100)
            .attr("stroke", 
              d3.rgb(if d3.select(this).classed("in") then inboundColor else outboundColor).brighter(0.5))

        .on "mouseout", (d) ->
          d3.select(this)
            .transition()
            .duration(100)
            .attr("stroke", if d3.select(this).classed("in") then inboundColor else outboundColor)
        ###

      $('line').tipsy
        gravity: 'w'
        opacity: 0.9
        html: true
        trigger: "manual"
        title: ->
          flowTooltip(d3.select(this).data()[0])


    bubble = svg.selectAll("g.bubble")
        .data(nodes)
      .enter()
        .append("g")
          .attr("class", "bubble")
          .on 'click', (d) ->

            if selectedNode == this
              selectedNode = null
              d3.select(this).selectAll("circle").classed("selected", false)
            else 
              if selectedNode != null
                d3.select(selectedNode).selectAll("circle").classed("selected", false)
                flows.selectAll("line").remove()
              selectedNode = this
              d3.select(this).selectAll("circle").classed("selected", true)
              showFlowsOf this


          .on 'mouseover', (d) ->
            if selectedNode == null
              showFlowsOf this

          .on 'mouseout', (d) ->
            if selectedNode == null
              flows.selectAll("line").remove()


    clearNodeSelection = ->
      if selectedNode != null
        d3.select(selectedNode).selectAll("circle").classed("selected", false)
        flows.selectAll("line").remove()
        selectedNode = null

    $(document).keyup (e) -> if e.keyCode == 27 then clearNodeSelection()


    bubble.append("circle")
      .attr("class", "rin")
      .attr("opacity", 0.5)
      .attr("fill", "#f00")

    bubble.append("circle")
      .attr("class", "rout")
      .attr("opacity", 0.5)
      .attr("fill", "#00f")


    bubble.append("text")
      .attr("class", "nodeLabel")
      .attr("y", 5)
      .attr("font-size", 9)
      .attr("text-anchor", "middle")
      .text((d)-> if d.code.length < 7 then d.code else d.code.substring(0,5)+".." )




    svg.append("text")
      .attr("id", "yearText")
      .attr("x", bubblesChartWidth - 20)
      .attr("y", 100)
      .attr("text-anchor", "end")
        .text(state.selMagnAttr())

    updateYear = (e, ui, noAnim) ->
      unless state.selAttrIndex == ui.value
        state.selAttrIndex = ui.value
        update(noAnim)

    update = (noAnim) ->
      updateNodeSizes()
      duration = if noAnim then 0 else 200

      svg.selectAll("#yearText")
        .text(state.selMagnAttr())

      bubble.selectAll("circle.rin")
        .transition()
        .duration(duration)
        .attr("r", (d) -> d.rin)
      
      bubble.selectAll("circle.rout")
        .transition()
        .duration(duration)
        .attr("r", (d) -> d.rout)

      bubble.selectAll("text.nodeLabel")
        .attr("visibility", (d) -> if d.r > 10 then "visible" else "hidden")

      flows.selectAll("line")
        .transition()
        .duration(duration)
        .attr("stroke-width", (d) -> fwscale(v(d)))
        .attr("visibility", (d) -> if v(d) > 0 then "visible" else "hidden")

      force.start()

    update()


    $("#yearSlider")
      .slider
        min: 0
        max: state.magnAttrs().length - 1
        value: state.magnAttrs().length - 1
        slide: (e, ui) -> updateYear(e, ui, false)
        change: (e, ui) -> updateYear(e, ui, false)

    #$("#playButton").button()

    $('g.bubble').tipsy
      gravity: 'w'
      html: true
      opacity: 0.9
      title: ->
        bubbleTooltip(d3.select(this).data()[0])



    timer = undefined

    stop = ->
      clearInterval(timer)
      timer = undefined
      $(play).html("Play")
    

    $("#play").click ->
      if timer
        stop()
      else
        $(play).html("Stop");

        if state.selAttrIndex == state.magnAttrs().length - 1
          state.selAttrIndex = 0
        else
          state.selAttrIndex++

        $("#yearSlider").slider('value', state.selAttrIndex);
        update()

        timer = setInterval(->
          if (state.selAttrIndex >= state.magnAttrs().length - 1) 
            stop()
          else
            state.selAttrIndex++
            $("#yearSlider").slider('value', state.selAttrIndex)
            update()

        , 900)


