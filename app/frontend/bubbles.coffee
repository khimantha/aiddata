years = [1947..2011]
startYear = 2007

# Bubbles
bubbles = bubblesChart()
  .conf(
    flowOriginAttr: 'donor'
    flowDestAttr: 'recipient'
    nodeIdAttr: 'code'
    nodeLabelAttr: 'name'
    latAttr: 'Lat'
    lonAttr: 'Lon'
    flowMagnAttrs: years
    )
  .on "changeSelDate", (current, old) -> timeSlider.setTime(current)


barHierarchy = barHierarchyChart()
  .width(400)
  .barHeight(10)
  .labelsWidth(200)
  .childrenAttr("values")
  .nameAttr("name")
  .valueFormat(formatMagnitude)
  .values((d) -> d["sum_#{startYear}"] ? 0)
  # .values((d) -> d.totals[startYear].sum ? 0)
  #.values((d) -> d.totals["sum_#{startYear}"] ? 0)
  .labelsFormat((d) -> shorten(d.name ? d.key, 35))
  .labelsTooltipFormat((d) -> name = d.name ? d.key)
  .breadcrumbText(
    do ->
      percentageFormat = d3.format(",.2%")
      (currentNode) ->
        v = barHierarchy.values()
        data = currentNode; (data = data.parent while data.parent?)
        formatMagnitude(v(currentNode)) + " (" + 
        percentageFormat(v(currentNode) / v(data)) + " of total)"
  )


groupFlowsByOD = (flowList) -> 
  nested = d3.nest()
    .key((d) -> d.donor)
    .key((d) -> d.recipient)
    .key((d) -> d.date)
    .entries(flowList)

  flows = []
  for o in nested
    for d in o.values
      entry =
        donor : o.key
        recipient : d.key

      for val in d.values
        entry[val.key] = val.values[0].sum_amount_usd_constant

      flows.push entry
  flows


timeSlider = timeSliderControl()
  .min(utils.date.yearToDate(years[0]))
  .max(utils.date.yearToDate(years[years.length - 1]))
  .step(d3.time.year)
  .format(d3.time.format("%Y"))
  .width(250 - 30 - 8) # timeSeries margins
  .height(10)
  .on "change", (current, old) ->
    bubbles.setSelDateTo(current, true)
    barHierarchy.values((d) -> d["sum_" + utils.date.dateToYear(current)] ? 0)

loadData()
  .csv('nodes', "#{dynamicDataPath}aiddata-nodes.csv")
  #.csv('flows', "#{dynamicDataPath}aiddata-totals-d-r-y.csv")
  .csv('flows', "dv/flows/by/od.csv")
  .json('map', "data/world-countries.json")
  .csv('countries', "data/aiddata-countries.csv")
  .csv('flowsByPurpose', "dv/flows/by/purpose.csv")
  .json('purposeTree', "purposes-with-totals.json")
  .onload (data) ->


    # list of flows with every year separated
    #   -> list grouped by o/d, all years' values in one object
    data.flows = groupFlowsByOD data.flows 

    provideCountryNodesWithCoords(
      data.nodes, { code: 'code', lat: 'Lat', lon: 'Lon'},
      data.countries, { code: "Code", lat: "Lat", lon: "Lon" }
    )

    d3.select("#bubblesChart")
      .datum(data)
      .call(bubbles)


    d3.select("#timeSlider")
      .call(timeSlider)

    # purposes = d3.nest()
    #   .key((d) -> d.date)
    #   .map(data.purposes)

    valueAttrs = do ->
      arr = []
      for y in years
        for attr in ["sum", "count"]
          arr.push "#{attr}_#{y}"
      arr

    utils.aiddata.purposes.provideWithTotals(data.purposeTree, valueAttrs, "values", "totals")

    d3.select("#purposeBars")
      .datum(data.purposeTree) #utils.aiddata.purposes.fromCsv(purposes['2007']))
      .call(barHierarchy)

    bubbles.setSelDateTo(utils.date.yearToDate(startYear), true)

    $("#loading").remove()


