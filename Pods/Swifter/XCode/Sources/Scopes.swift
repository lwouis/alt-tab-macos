//
//  HttpHandlers+Scopes.swift
//  Swifter
//
//  Copyright © 2014-2016 Damian Kołakowski. All rights reserved.
//

// swiftlint:disable file_length
import Foundation

public func scopes(_ scope: @escaping Closure) -> ((HttpRequest) -> HttpResponse) {
    return { _ in
        scopesBuffer[Process.tid] = ""
        scope()
        return .raw(200, "OK", ["Content-Type": "text/html"], {
            try? $0.write([UInt8](("<!DOCTYPE html>"  + (scopesBuffer[Process.tid] ?? "")).utf8))
        })
    }
}

public typealias Closure = () -> Void

public var idd: String?
public var dir: String?
public var rel: String?
public var rev: String?
public var alt: String?
public var forr: String?
public var src: String?
public var type: String?
public var href: String?
public var text: String?
public var abbr: String?
public var size: String?
public var face: String?
public var char: String?
public var cite: String?
public var span: String?
public var data: String?
public var axis: String?
public var Name: String?
public var name: String?
public var code: String?
public var link: String?
public var lang: String?
public var cols: String?
public var rows: String?
public var ismap: String?
public var shape: String?
public var style: String?
public var alink: String?
public var width: String?
public var rules: String?
public var align: String?
public var frame: String?
public var vlink: String?
public var deferr: String?
public var color: String?
public var media: String?
public var title: String?
public var scope: String?
public var classs: String?
public var manifest: String?
public var value: String?
public var clear: String?
public var start: String?
public var label: String?
public var action: String?
public var height: String?
public var method: String?
public var acceptt: String?
public var object: String?
public var scheme: String?
public var coords: String?
public var usemap: String?
public var onblur: String?
public var nohref: String?
public var nowrap: String?
public var hspace: String?
public var border: String?
public var valign: String?
public var vspace: String?
public var onload: String?
public var target: String?
public var prompt: String?
public var onfocus: String?
public var enctype: String?
public var onclick: String?
public var ontouchstart: String?
public var onkeyup: String?
public var profile: String?
public var version: String?
public var onreset: String?
public var charset: String?
public var standby: String?
public var colspan: String?
public var charoff: String?
public var classid: String?
public var compact: String?
public var declare: String?
public var rowspan: String?
public var checked: String?
public var archive: String?
public var bgcolor: String?
public var content: String?
public var noshade: String?
public var summary: String?
public var headers: String?
public var onselect: String?
public var readonly: String?
public var tabindex: String?
public var onchange: String?
public var noresize: String?
public var disabled: String?
public var longdesc: String?
public var codebase: String?
public var language: String?
public var datetime: String?
public var selected: String?
public var hreflang: String?
public var onsubmit: String?
public var multiple: String?
public var onunload: String?
public var codetype: String?
public var scrolling: String?
public var onkeydown: String?
public var maxlength: String?
public var valuetype: String?
public var accesskey: String?
public var onmouseup: String?
public var autofocus: String?
public var onkeypress: String?
public var ondblclick: String?
public var onmouseout: String?
public var httpEquiv: String?
public var dataText: String?
public var background: String?
public var onmousemove: String?
public var onmouseover: String?
public var cellpadding: String?
public var onmousedown: String?
public var frameborder: String?
public var marginwidth: String?
public var cellspacing: String?
public var placeholder: String?
public var marginheight: String?
public var acceptCharset: String?

public var inner: String?

public func a(_ closure: Closure) { element("a", closure) }
public func b(_ closure: Closure) { element("b", closure) }
public func i(_ closure: Closure) { element("i", closure) }
public func p(_ closure: Closure) { element("p", closure) }
public func q(_ closure: Closure) { element("q", closure) }
public func s(_ closure: Closure) { element("s", closure) }
public func u(_ closure: Closure) { element("u", closure) }

public func br(_ closure: Closure) { element("br", closure) }
public func dd(_ closure: Closure) { element("dd", closure) }
public func dl(_ closure: Closure) { element("dl", closure) }
public func dt(_ closure: Closure) { element("dt", closure) }
public func em(_ closure: Closure) { element("em", closure) }
public func hr(_ closure: Closure) { element("hr", closure) }
public func li(_ closure: Closure) { element("li", closure) }
public func ol(_ closure: Closure) { element("ol", closure) }
public func rp(_ closure: Closure) { element("rp", closure) }
public func rt(_ closure: Closure) { element("rt", closure) }
public func td(_ closure: Closure) { element("td", closure) }
public func th(_ closure: Closure) { element("th", closure) }
public func tr(_ closure: Closure) { element("tr", closure) }
public func tt(_ closure: Closure) { element("tt", closure) }
public func ul(_ closure: Closure) { element("ul", closure) }

public func ul<T: Sequence>(_ collection: T, _ closure: @escaping (T.Iterator.Element) -> Void) {
    element("ul", {
        for item in collection {
            closure(item)
        }
    })
}

public func h1(_ closure: Closure) { element("h1", closure) }
public func h2(_ closure: Closure) { element("h2", closure) }
public func h3(_ closure: Closure) { element("h3", closure) }
public func h4(_ closure: Closure) { element("h4", closure) }
public func h5(_ closure: Closure) { element("h5", closure) }
public func h6(_ closure: Closure) { element("h6", closure) }

public func bdi(_ closure: Closure) { element("bdi", closure) }
public func bdo(_ closure: Closure) { element("bdo", closure) }
public func big(_ closure: Closure) { element("big", closure) }
public func col(_ closure: Closure) { element("col", closure) }
public func del(_ closure: Closure) { element("del", closure) }
public func dfn(_ closure: Closure) { element("dfn", closure) }
public func dir(_ closure: Closure) { element("dir", closure) }
public func div(_ closure: Closure) { element("div", closure) }
public func img(_ closure: Closure) { element("img", closure) }
public func ins(_ closure: Closure) { element("ins", closure) }
public func kbd(_ closure: Closure) { element("kbd", closure) }
public func map(_ closure: Closure) { element("map", closure) }
public func nav(_ closure: Closure) { element("nav", closure) }
public func pre(_ closure: Closure) { element("pre", closure) }
public func rtc(_ closure: Closure) { element("rtc", closure) }
public func sub(_ closure: Closure) { element("sub", closure) }
public func sup(_ closure: Closure) { element("sup", closure) }

public func varr(_ closure: Closure) { element("var", closure) }
public func wbr(_ closure: Closure) { element("wbr", closure) }
public func xmp(_ closure: Closure) { element("xmp", closure) }

public func abbr(_ closure: Closure) { element("abbr", closure) }
public func area(_ closure: Closure) { element("area", closure) }
public func base(_ closure: Closure) { element("base", closure) }
public func body(_ closure: Closure) { element("body", closure) }
public func cite(_ closure: Closure) { element("cite", closure) }
public func code(_ closure: Closure) { element("code", closure) }
public func data(_ closure: Closure) { element("data", closure) }
public func font(_ closure: Closure) { element("font", closure) }
public func form(_ closure: Closure) { element("form", closure) }
public func head(_ closure: Closure) { element("head", closure) }
public func html(_ closure: Closure) { element("html", closure) }
public func link(_ closure: Closure) { element("link", closure) }
public func main(_ closure: Closure) { element("main", closure) }
public func mark(_ closure: Closure) { element("mark", closure) }
public func menu(_ closure: Closure) { element("menu", closure) }
public func meta(_ closure: Closure) { element("meta", closure) }
public func nobr(_ closure: Closure) { element("nobr", closure) }
public func ruby(_ closure: Closure) { element("ruby", closure) }
public func samp(_ closure: Closure) { element("samp", closure) }
public func span(_ closure: Closure) { element("span", closure) }
public func time(_ closure: Closure) { element("time", closure) }

public func aside(_ closure: Closure) { element("aside", closure) }
public func audio(_ closure: Closure) { element("audio", closure) }
public func blink(_ closure: Closure) { element("blink", closure) }
public func embed(_ closure: Closure) { element("embed", closure) }
public func frame(_ closure: Closure) { element("frame", closure) }
public func image(_ closure: Closure) { element("image", closure) }
public func input(_ closure: Closure) { element("input", closure) }
public func label(_ closure: Closure) { element("label", closure) }
public func meter(_ closure: Closure) { element("meter", closure) }
public func param(_ closure: Closure) { element("param", closure) }
public func small(_ closure: Closure) { element("small", closure) }
public func style(_ closure: Closure) { element("style", closure) }
public func table(_ closure: Closure) { element("table", closure) }

public func table<T: Sequence>(_ collection: T, closure: @escaping (T.Iterator.Element) -> Void) {
    element("table", {
        for item in collection {
            closure(item)
        }
    })
}

public func tbody(_ closure: Closure) { element("tbody", closure) }

public func tbody<T: Sequence>(_ collection: T, closure: @escaping (T.Iterator.Element) -> Void) {
    element("tbody", {
        for item in collection {
            closure(item)
        }
    })
}

public func tfoot(_ closure: Closure) { element("tfoot", closure) }
public func thead(_ closure: Closure) { element("thead", closure) }
public func title(_ closure: Closure) { element("title", closure) }
public func track(_ closure: Closure) { element("track", closure) }
public func video(_ closure: Closure) { element("video", closure) }

public func applet(_ closure: Closure) { element("applet", closure) }
public func button(_ closure: Closure) { element("button", closure) }
public func canvas(_ closure: Closure) { element("canvas", closure) }
public func center(_ closure: Closure) { element("center", closure) }
public func dialog(_ closure: Closure) { element("dialog", closure) }
public func figure(_ closure: Closure) { element("figure", closure) }
public func footer(_ closure: Closure) { element("footer", closure) }
public func header(_ closure: Closure) { element("header", closure) }
public func hgroup(_ closure: Closure) { element("hgroup", closure) }
public func iframe(_ closure: Closure) { element("iframe", closure) }
public func keygen(_ closure: Closure) { element("keygen", closure) }
public func legend(_ closure: Closure) { element("legend", closure) }
public func object(_ closure: Closure) { element("object", closure) }
public func option(_ closure: Closure) { element("option", closure) }
public func output(_ closure: Closure) { element("output", closure) }
public func script(_ closure: Closure) { element("script", closure) }
public func select(_ closure: Closure) { element("select", closure) }
public func shadow(_ closure: Closure) { element("shadow", closure) }
public func source(_ closure: Closure) { element("source", closure) }
public func spacer(_ closure: Closure) { element("spacer", closure) }
public func strike(_ closure: Closure) { element("strike", closure) }
public func strong(_ closure: Closure) { element("strong", closure) }

public func acronym(_ closure: Closure) { element("acronym", closure) }
public func address(_ closure: Closure) { element("address", closure) }
public func article(_ closure: Closure) { element("article", closure) }
public func bgsound(_ closure: Closure) { element("bgsound", closure) }
public func caption(_ closure: Closure) { element("caption", closure) }
public func command(_ closure: Closure) { element("command", closure) }
public func content(_ closure: Closure) { element("content", closure) }
public func details(_ closure: Closure) { element("details", closure) }
public func elementt(_ closure: Closure) { element("element", closure) }
public func isindex(_ closure: Closure) { element("isindex", closure) }
public func listing(_ closure: Closure) { element("listing", closure) }
public func marquee(_ closure: Closure) { element("marquee", closure) }
public func noembed(_ closure: Closure) { element("noembed", closure) }
public func picture(_ closure: Closure) { element("picture", closure) }
public func section(_ closure: Closure) { element("section", closure) }
public func summary(_ closure: Closure) { element("summary", closure) }

public func basefont(_ closure: Closure) { element("basefont", closure) }
public func colgroup(_ closure: Closure) { element("colgroup", closure) }
public func datalist(_ closure: Closure) { element("datalist", closure) }
public func fieldset(_ closure: Closure) { element("fieldset", closure) }
public func frameset(_ closure: Closure) { element("frameset", closure) }
public func menuitem(_ closure: Closure) { element("menuitem", closure) }
public func multicol(_ closure: Closure) { element("multicol", closure) }
public func noframes(_ closure: Closure) { element("noframes", closure) }
public func noscript(_ closure: Closure) { element("noscript", closure) }
public func optgroup(_ closure: Closure) { element("optgroup", closure) }
public func progress(_ closure: Closure) { element("progress", closure) }
public func template(_ closure: Closure) { element("template", closure) }
public func textarea(_ closure: Closure) { element("textarea", closure) }

public func plaintext(_ closure: Closure) { element("plaintext", closure) }
public func javascript(_ closure: Closure) { element("script", ["type": "text/javascript"], closure) }
public func blockquote(_ closure: Closure) { element("blockquote", closure) }
public func figcaption(_ closure: Closure) { element("figcaption", closure) }

public func stylesheet(_ closure: Closure) { element("link", ["rel": "stylesheet", "type": "text/css"], closure) }

public func element(_ node: String, _ closure: Closure) { evaluate(node, [:], closure) }
public func element(_ node: String, _ attrs: [String: String?] = [:], _ closure: Closure) { evaluate(node, attrs, closure) }

var scopesBuffer = [UInt64: String]()

// swiftlint:disable cyclomatic_complexity function_body_length
private func evaluate(_ node: String, _ attrs: [String: String?] = [:], _ closure: Closure) {

    // Push the attributes.

    let stackid = idd
    let stackdir = dir
    let stackrel = rel
    let stackrev = rev
    let stackalt = alt
    let stackfor = forr
    let stacksrc = src
    let stacktype = type
    let stackhref = href
    let stacktext = text
    let stackabbr = abbr
    let stacksize = size
    let stackface = face
    let stackchar = char
    let stackcite = cite
    let stackspan = span
    let stackdata = data
    let stackaxis = axis
    let stackName = Name
    let stackname = name
    let stackcode = code
    let stacklink = link
    let stacklang = lang
    let stackcols = cols
    let stackrows = rows
    let stackismap = ismap
    let stackshape = shape
    let stackstyle = style
    let stackalink = alink
    let stackwidth = width
    let stackrules = rules
    let stackalign = align
    let stackframe = frame
    let stackvlink = vlink
    let stackdefer = deferr
    let stackcolor = color
    let stackmedia = media
    let stacktitle = title
    let stackscope = scope
    let stackclass = classs
    let stackmanifest = manifest
    let stackvalue = value
    let stackclear = clear
    let stackstart = start
    let stacklabel = label
    let stackaction = action
    let stackheight = height
    let stackmethod = method
    let stackaccept = acceptt
    let stackobject = object
    let stackscheme = scheme
    let stackcoords = coords
    let stackusemap = usemap
    let stackonblur = onblur
    let stacknohref = nohref
    let stacknowrap = nowrap
    let stackhspace = hspace
    let stackborder = border
    let stackvalign = valign
    let stackvspace = vspace
    let stackonload = onload
    let stacktarget = target
    let stackprompt = prompt
    let stackonfocus = onfocus
    let stackenctype = enctype
    let stackonclick = onclick
    let stackontouchstart = ontouchstart
    let stackonkeyup = onkeyup
    let stackprofile = profile
    let stackversion = version
    let stackonreset = onreset
    let stackcharset = charset
    let stackstandby = standby
    let stackcolspan = colspan
    let stackcharoff = charoff
    let stackclassid = classid
    let stackcompact = compact
    let stackdeclare = declare
    let stackrowspan = rowspan
    let stackchecked = checked
    let stackarchive = archive
    let stackbgcolor = bgcolor
    let stackcontent = content
    let stacknoshade = noshade
    let stacksummary = summary
    let stackheaders = headers
    let stackonselect = onselect
    let stackreadonly = readonly
    let stacktabindex = tabindex
    let stackonchange = onchange
    let stacknoresize = noresize
    let stackdisabled = disabled
    let stacklongdesc = longdesc
    let stackcodebase = codebase
    let stacklanguage = language
    let stackdatetime = datetime
    let stackselected = selected
    let stackhreflang = hreflang
    let stackonsubmit = onsubmit
    let stackmultiple = multiple
    let stackonunload = onunload
    let stackcodetype = codetype
    let stackscrolling = scrolling
    let stackonkeydown = onkeydown
    let stackmaxlength = maxlength
    let stackvaluetype = valuetype
    let stackaccesskey = accesskey
    let stackonmouseup = onmouseup
    let stackonkeypress = onkeypress
    let stackondblclick = ondblclick
    let stackonmouseout = onmouseout
    let stackhttpEquiv = httpEquiv
    let stackdataText = dataText
    let stackbackground = background
    let stackonmousemove = onmousemove
    let stackonmouseover = onmouseover
    let stackcellpadding = cellpadding
    let stackonmousedown = onmousedown
    let stackframeborder = frameborder
    let stackmarginwidth = marginwidth
    let stackcellspacing = cellspacing
    let stackplaceholder = placeholder
    let stackmarginheight = marginheight
    let stackacceptCharset = acceptCharset
    let stackinner = inner

    // Reset the values before a nested scope evalutation.

    idd = nil
    dir = nil
    rel = nil
    rev = nil
    alt = nil
    forr = nil
    src = nil
    type = nil
    href = nil
    text = nil
    abbr = nil
    size = nil
    face = nil
    char = nil
    cite = nil
    span = nil
    data = nil
    axis = nil
    Name = nil
    name = nil
    code = nil
    link = nil
    lang = nil
    cols = nil
    rows = nil
    ismap = nil
    shape = nil
    style = nil
    alink = nil
    width = nil
    rules = nil
    align = nil
    frame = nil
    vlink = nil
    deferr = nil
    color = nil
    media = nil
    title = nil
    scope = nil
    classs = nil
    manifest = nil
    value = nil
    clear = nil
    start = nil
    label = nil
    action = nil
    height = nil
    method = nil
    acceptt = nil
    object = nil
    scheme = nil
    coords = nil
    usemap = nil
    onblur = nil
    nohref = nil
    nowrap = nil
    hspace = nil
    border = nil
    valign = nil
    vspace = nil
    onload = nil
    target = nil
    prompt = nil
    onfocus = nil
    enctype = nil
    onclick = nil
    ontouchstart = nil
    onkeyup = nil
    profile = nil
    version = nil
    onreset = nil
    charset = nil
    standby = nil
    colspan = nil
    charoff = nil
    classid = nil
    compact = nil
    declare = nil
    rowspan = nil
    checked = nil
    archive = nil
    bgcolor = nil
    content = nil
    noshade = nil
    summary = nil
    headers = nil
    onselect = nil
    readonly = nil
    tabindex = nil
    onchange = nil
    noresize = nil
    disabled = nil
    longdesc = nil
    codebase = nil
    language = nil
    datetime = nil
    selected = nil
    hreflang = nil
    onsubmit = nil
    multiple = nil
    onunload = nil
    codetype = nil
    scrolling = nil
    onkeydown = nil
    maxlength = nil
    valuetype = nil
    accesskey = nil
    onmouseup = nil
    onkeypress = nil
    ondblclick = nil
    onmouseout = nil
    httpEquiv = nil
    dataText = nil
    background = nil
    onmousemove = nil
    onmouseover = nil
    cellpadding = nil
    onmousedown = nil
    frameborder = nil
    placeholder = nil
    marginwidth = nil
    cellspacing = nil
    marginheight = nil
    acceptCharset = nil
    inner = nil

    scopesBuffer[Process.tid] = (scopesBuffer[Process.tid] ?? "") + "<" + node

    // Save the current output before the nested scope evalutation.

    var output = scopesBuffer[Process.tid] ?? ""

    // Clear the output buffer for the evalutation.

    scopesBuffer[Process.tid] = ""

    // Evaluate the nested scope.

    closure()

    // Render attributes set by the evalutation.

    var mergedAttributes = [String: String?]()

    if let idd = idd { mergedAttributes["id"] = idd }
    if let dir = dir { mergedAttributes["dir"] = dir }
    if let rel = rel { mergedAttributes["rel"] = rel }
    if let rev = rev { mergedAttributes["rev"] = rev }
    if let alt = alt { mergedAttributes["alt"] = alt }
    if let forr = forr { mergedAttributes["for"] = forr }
    if let src = src { mergedAttributes["src"] = src }
    if let type = type { mergedAttributes["type"] = type }
    if let href = href { mergedAttributes["href"] = href }
    if let text = text { mergedAttributes["text"] = text }
    if let abbr = abbr { mergedAttributes["abbr"] = abbr }
    if let size = size { mergedAttributes["size"] = size }
    if let face = face { mergedAttributes["face"] = face }
    if let char = char { mergedAttributes["char"] = char }
    if let cite = cite { mergedAttributes["cite"] = cite }
    if let span = span { mergedAttributes["span"] = span }
    if let data = data { mergedAttributes["data"] = data }
    if let axis = axis { mergedAttributes["axis"] = axis }
    if let Name = Name { mergedAttributes["Name"] = Name }
    if let name = name { mergedAttributes["name"] = name }
    if let code = code { mergedAttributes["code"] = code }
    if let link = link { mergedAttributes["link"] = link }
    if let lang = lang { mergedAttributes["lang"] = lang }
    if let cols = cols { mergedAttributes["cols"] = cols }
    if let rows = rows { mergedAttributes["rows"] = rows }
    if let ismap = ismap { mergedAttributes["ismap"] = ismap }
    if let shape = shape { mergedAttributes["shape"] = shape }
    if let style = style { mergedAttributes["style"] = style }
    if let alink = alink { mergedAttributes["alink"] = alink }
    if let width = width { mergedAttributes["width"] = width }
    if let rules = rules { mergedAttributes["rules"] = rules }
    if let align = align { mergedAttributes["align"] = align }
    if let frame = frame { mergedAttributes["frame"] = frame }
    if let vlink = vlink { mergedAttributes["vlink"] = vlink }
    if let deferr = deferr { mergedAttributes["defer"] = deferr }
    if let color = color { mergedAttributes["color"] = color }
    if let media = media { mergedAttributes["media"] = media }
    if let title = title { mergedAttributes["title"] = title }
    if let scope = scope { mergedAttributes["scope"] = scope }
    if let classs = classs { mergedAttributes["class"] = classs }
    if let manifest = manifest { mergedAttributes["manifest"] = manifest }
    if let value = value { mergedAttributes["value"] = value }
    if let clear = clear { mergedAttributes["clear"] = clear }
    if let start = start { mergedAttributes["start"] = start }
    if let label = label { mergedAttributes["label"] = label }
    if let action = action { mergedAttributes["action"] = action }
    if let height = height { mergedAttributes["height"] = height }
    if let method = method { mergedAttributes["method"] = method }
    if let acceptt = acceptt { mergedAttributes["accept"] = acceptt }
    if let object = object { mergedAttributes["object"] = object }
    if let scheme = scheme { mergedAttributes["scheme"] = scheme }
    if let coords = coords { mergedAttributes["coords"] = coords }
    if let usemap = usemap { mergedAttributes["usemap"] = usemap }
    if let onblur = onblur { mergedAttributes["onblur"] = onblur }
    if let nohref = nohref { mergedAttributes["nohref"] = nohref }
    if let nowrap = nowrap { mergedAttributes["nowrap"] = nowrap }
    if let hspace = hspace { mergedAttributes["hspace"] = hspace }
    if let border = border { mergedAttributes["border"] = border }
    if let valign = valign { mergedAttributes["valign"] = valign }
    if let vspace = vspace { mergedAttributes["vspace"] = vspace }
    if let onload = onload { mergedAttributes["onload"] = onload }
    if let target = target { mergedAttributes["target"] = target }
    if let prompt = prompt { mergedAttributes["prompt"] = prompt }
    if let onfocus = onfocus { mergedAttributes["onfocus"] = onfocus }
    if let enctype = enctype { mergedAttributes["enctype"] = enctype }
    if let onclick = onclick { mergedAttributes["onclick"] = onclick }
    if let ontouchstart = ontouchstart { mergedAttributes["ontouchstart"] = ontouchstart }
    if let onkeyup = onkeyup { mergedAttributes["onkeyup"] = onkeyup }
    if let profile = profile { mergedAttributes["profile"] = profile }
    if let version = version { mergedAttributes["version"] = version }
    if let onreset = onreset { mergedAttributes["onreset"] = onreset }
    if let charset = charset { mergedAttributes["charset"] = charset }
    if let standby = standby { mergedAttributes["standby"] = standby }
    if let colspan = colspan { mergedAttributes["colspan"] = colspan }
    if let charoff = charoff { mergedAttributes["charoff"] = charoff }
    if let classid = classid { mergedAttributes["classid"] = classid }
    if let compact = compact { mergedAttributes["compact"] = compact }
    if let declare = declare { mergedAttributes["declare"] = declare }
    if let rowspan = rowspan { mergedAttributes["rowspan"] = rowspan }
    if let checked = checked { mergedAttributes["checked"] = checked }
    if let archive = archive { mergedAttributes["archive"] = archive }
    if let bgcolor = bgcolor { mergedAttributes["bgcolor"] = bgcolor }
    if let content = content { mergedAttributes["content"] = content }
    if let noshade = noshade { mergedAttributes["noshade"] = noshade }
    if let summary = summary { mergedAttributes["summary"] = summary }
    if let headers = headers { mergedAttributes["headers"] = headers }
    if let onselect = onselect { mergedAttributes["onselect"] = onselect }
    if let readonly = readonly { mergedAttributes["readonly"] = readonly }
    if let tabindex = tabindex { mergedAttributes["tabindex"] = tabindex }
    if let onchange = onchange { mergedAttributes["onchange"] = onchange }
    if let noresize = noresize { mergedAttributes["noresize"] = noresize }
    if let disabled = disabled { mergedAttributes["disabled"] = disabled }
    if let longdesc = longdesc { mergedAttributes["longdesc"] = longdesc }
    if let codebase = codebase { mergedAttributes["codebase"] = codebase }
    if let language = language { mergedAttributes["language"] = language }
    if let datetime = datetime { mergedAttributes["datetime"] = datetime }
    if let selected = selected { mergedAttributes["selected"] = selected }
    if let hreflang = hreflang { mergedAttributes["hreflang"] = hreflang }
    if let onsubmit = onsubmit { mergedAttributes["onsubmit"] = onsubmit }
    if let multiple = multiple { mergedAttributes["multiple"] = multiple }
    if let onunload = onunload { mergedAttributes["onunload"] = onunload }
    if let codetype = codetype { mergedAttributes["codetype"] = codetype }
    if let scrolling = scrolling { mergedAttributes["scrolling"] = scrolling }
    if let onkeydown = onkeydown { mergedAttributes["onkeydown"] = onkeydown }
    if let maxlength = maxlength { mergedAttributes["maxlength"] = maxlength }
    if let valuetype = valuetype { mergedAttributes["valuetype"] = valuetype }
    if let accesskey = accesskey { mergedAttributes["accesskey"] = accesskey }
    if let onmouseup = onmouseup { mergedAttributes["onmouseup"] = onmouseup }
    if let onkeypress = onkeypress { mergedAttributes["onkeypress"] = onkeypress }
    if let ondblclick = ondblclick { mergedAttributes["ondblclick"] = ondblclick }
    if let onmouseout = onmouseout { mergedAttributes["onmouseout"] = onmouseout }
    if let httpEquiv = httpEquiv { mergedAttributes["http-equiv"] = httpEquiv }
    if let dataText = dataText { mergedAttributes["data-text"] = dataText }
    if let background = background { mergedAttributes["background"] = background }
    if let onmousemove = onmousemove { mergedAttributes["onmousemove"] = onmousemove }
    if let onmouseover = onmouseover { mergedAttributes["onmouseover"] = onmouseover }
    if let cellpadding = cellpadding { mergedAttributes["cellpadding"] = cellpadding }
    if let onmousedown = onmousedown { mergedAttributes["onmousedown"] = onmousedown }
    if let frameborder = frameborder { mergedAttributes["frameborder"] = frameborder }
    if let marginwidth = marginwidth { mergedAttributes["marginwidth"] = marginwidth }
    if let cellspacing = cellspacing { mergedAttributes["cellspacing"] = cellspacing }
    if let placeholder = placeholder { mergedAttributes["placeholder"] = placeholder }
    if let marginheight = marginheight { mergedAttributes["marginheight"] = marginheight }
    if let acceptCharset = acceptCharset { mergedAttributes["accept-charset"] = acceptCharset }

    for item in attrs.enumerated() {
        mergedAttributes.updateValue(item.element.1, forKey: item.element.0)
    }

    output += mergedAttributes.reduce("") { result, item in
        if let value = item.value {
            return result + " \(item.key)=\"\(value)\""
        } else {
            return result
        }
    }

    if let inner = inner {
        scopesBuffer[Process.tid] = output + ">" + (inner) + "</" + node + ">"
    } else {
        let current = scopesBuffer[Process.tid]  ?? ""
        scopesBuffer[Process.tid] = output + ">" + current + "</" + node + ">"
    }

    // Pop the attributes.

    idd = stackid
    dir = stackdir
    rel = stackrel
    rev = stackrev
    alt = stackalt
    forr = stackfor
    src = stacksrc
    type = stacktype
    href = stackhref
    text = stacktext
    abbr = stackabbr
    size = stacksize
    face = stackface
    char = stackchar
    cite = stackcite
    span = stackspan
    data = stackdata
    axis = stackaxis
    Name = stackName
    name = stackname
    code = stackcode
    link = stacklink
    lang = stacklang
    cols = stackcols
    rows = stackrows
    ismap = stackismap
    shape = stackshape
    style = stackstyle
    alink = stackalink
    width = stackwidth
    rules = stackrules
    align = stackalign
    frame = stackframe
    vlink = stackvlink
    deferr = stackdefer
    color = stackcolor
    media = stackmedia
    title = stacktitle
    scope = stackscope
    classs = stackclass
    manifest = stackmanifest
    value = stackvalue
    clear = stackclear
    start = stackstart
    label = stacklabel
    action = stackaction
    height = stackheight
    method = stackmethod
    acceptt = stackaccept
    object = stackobject
    scheme = stackscheme
    coords = stackcoords
    usemap = stackusemap
    onblur = stackonblur
    nohref = stacknohref
    nowrap = stacknowrap
    hspace = stackhspace
    border = stackborder
    valign = stackvalign
    vspace = stackvspace
    onload = stackonload
    target = stacktarget
    prompt = stackprompt
    onfocus = stackonfocus
    enctype = stackenctype
    onclick = stackonclick
    ontouchstart = stackontouchstart
    onkeyup = stackonkeyup
    profile = stackprofile
    version = stackversion
    onreset = stackonreset
    charset = stackcharset
    standby = stackstandby
    colspan = stackcolspan
    charoff = stackcharoff
    classid = stackclassid
    compact = stackcompact
    declare = stackdeclare
    rowspan = stackrowspan
    checked = stackchecked
    archive = stackarchive
    bgcolor = stackbgcolor
    content = stackcontent
    noshade = stacknoshade
    summary = stacksummary
    headers = stackheaders
    onselect = stackonselect
    readonly = stackreadonly
    tabindex = stacktabindex
    onchange = stackonchange
    noresize = stacknoresize
    disabled = stackdisabled
    longdesc = stacklongdesc
    codebase = stackcodebase
    language = stacklanguage
    datetime = stackdatetime
    selected = stackselected
    hreflang = stackhreflang
    onsubmit = stackonsubmit
    multiple = stackmultiple
    onunload = stackonunload
    codetype = stackcodetype
    scrolling = stackscrolling
    onkeydown = stackonkeydown
    maxlength = stackmaxlength
    valuetype = stackvaluetype
    accesskey = stackaccesskey
    onmouseup = stackonmouseup
    onkeypress = stackonkeypress
    ondblclick = stackondblclick
    onmouseout = stackonmouseout
    httpEquiv = stackhttpEquiv
    dataText = stackdataText
    background = stackbackground
    onmousemove = stackonmousemove
    onmouseover = stackonmouseover
    cellpadding = stackcellpadding
    onmousedown = stackonmousedown
    frameborder = stackframeborder
    placeholder = stackplaceholder
    marginwidth = stackmarginwidth
    cellspacing = stackcellspacing
    marginheight = stackmarginheight
    acceptCharset = stackacceptCharset

    inner = stackinner
}
