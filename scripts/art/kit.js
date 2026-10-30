// Renders the doc illustrations from small specs, in the style of jornada-do-developer.html.
// Each art is a `.art` element sized to its content; capture it at 2x into /images.

const SVG_NS = "http://www.w3.org/2000/svg"
let overlays = 0
const DARK = new URLSearchParams(location.search).get("theme") === "dark"
if (DARK) document.documentElement.classList.add("dark-theme")
document.addEventListener("DOMContentLoaded", () => { if (DARK) document.body.classList.add("dark") })
const INK = DARK ? ["#cbd5e1", "#8b9bb4"] : ["#334155", "#64748b"]

function el(tag, attrs = {}, html = "") {
  const node = document.createElement(tag)
  Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value))
  node.innerHTML = html
  return node
}

function icon(name) {
  return name ? `<i data-lucide="${name}"></i>` : ""
}

function overlay(art, width, height) {
  const svg = document.createElementNS(SVG_NS, "svg")
  svg.setAttribute("width", width)
  svg.setAttribute("height", height)
  svg.style.position = "absolute"
  svg.style.left = "0"
  svg.style.top = "0"
  svg.style.overflow = "visible"
  svg.dataset.heads = `o${(overlays += 1)}`
  svg.innerHTML = `<defs>${INK.map((color, i) =>
    `<marker id="${svg.dataset.heads}h${i}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
       <path d="M0,0 L10,5 L0,10 z" fill="${color}"/></marker>`).join("")}</defs>`
  art.appendChild(svg)
  return svg
}

function line(svg, points, { dashed = false, soft = false } = {}) {
  const path = document.createElementNS(SVG_NS, "path")
  path.setAttribute("d", points.map(([x, y], i) => `${i ? "L" : "M"}${x},${y}`).join(" "))
  path.setAttribute("fill", "none")
  path.setAttribute("stroke", soft ? INK[1] : INK[0])
  path.setAttribute("stroke-width", "2.2")
  if (dashed) path.setAttribute("stroke-dasharray", "7 6")
  path.setAttribute("marker-end", `url(#${svg.dataset.heads}h${soft ? 1 : 0})`)
  svg.appendChild(path)
}

// Sequence: participants side by side, one numbered message per row.
// steps: { from, to, text, reply } | { self, text } | { note, over } | { loop, steps } | { alt: [{ label, steps }] }
function sequence(art, { participants, steps, width = 1500, colWidth }) {
  const pad = 40
  const inner = width - pad * 2
  const col = colWidth || inner / participants.length
  const x = {}
  participants.forEach((p, i) => { x[p.id] = pad + col * i + col / 2 })

  const headerHeight = 112
  let y = 32 + headerHeight + 84
  let number = 0
  const rowHeight = 62
  const items = []

  const layout = (list, depth) => {
    list.forEach((step) => {
      if (step.loop) {
        const top = y - 14
        y += 26
        layout(step.steps, depth + 1)
        items.push({ kind: "loop", top, bottom: y - 22, depth, text: step.loop })
        y += 18
      } else if (step.alt) {
        const top = y - 14
        const dividers = []
        step.alt.forEach((branch, i) => {
          if (i) {
            dividers.push({ y: y - 24, label: branch.label })
            y += 14
          }
          y += 26
          layout(branch.steps, depth + 1)
        })
        items.push({ kind: "alt", top, bottom: y - 22, depth, text: step.alt[0].label, dividers })
        y += 18
      } else if (step.self) {
        number += 1
        items.push({ kind: "self", y, number, ...step })
        y += rowHeight + 16
      } else if (step.note) {
        items.push({ kind: "note", y: y - 24, ...step })
        y += 60
      } else {
        number += 1
        items.push({ kind: "msg", y, number, ...step })
        y += rowHeight
      }
    })
  }
  layout(steps, 0)

  const height = y + 10
  art.style.width = `${width}px`
  art.style.height = `${height}px`
  const svg = overlay(art, width, height)

  participants.forEach((p) => {
    const boxWidth = Math.min(col - 40, 300)
    const box = el("div", { class: `participant tone-${p.tone || "blue"}` },
      `${icon(p.icon)}<div class="t">${p.label}</div>${p.sub ? `<div class="s">${p.sub}</div>` : ""}`)
    box.style.left = `${x[p.id] - boxWidth / 2}px`
    box.style.width = `${boxWidth}px`
    box.style.top = "32px"
    art.appendChild(box)
    const life = document.createElementNS(SVG_NS, "path")
    life.setAttribute("d", `M${x[p.id]},${32 + headerHeight - 6} V${height - 16}`)
    life.setAttribute("stroke", DARK ? "#334155" : "#cbd5e1")
    life.setAttribute("stroke-width", "2")
    life.setAttribute("stroke-dasharray", "6 7")
    svg.insertBefore(life, svg.firstChild.nextSibling)
  })

  const tone = (id) => participants.find((p) => p.id === id)?.tone || "blue"

  const frame = (item, kind, iconName) => {
    const box = el("div", { class: `loop ${kind}` }, `<div class="ll">${icon(iconName)}${item.text}</div>`)
    const xs = Object.values(x)
    const inset = item.depth * 14
    const left = Math.max(12, Math.min(...xs) - col / 2 + 24 + inset)
    const right = Math.min(width - 12, Math.max(...xs) + col / 2 - 24 - inset)
    box.style.left = `${left}px`
    box.style.width = `${right - left}px`
    box.style.top = `${item.top}px`
    box.style.height = `${item.bottom - item.top}px`
    art.appendChild(box)
    return { left, right }
  }

  items.forEach((item) => {
    if (item.kind === "loop") {
      frame(item, "", "repeat")
    } else if (item.kind === "alt") {
      const { left, right } = frame(item, "alt", "git-branch")
      item.dividers.forEach((divider) => {
        const rule = document.createElementNS(SVG_NS, "path")
        rule.setAttribute("d", `M${left},${divider.y} H${right}`)
        rule.setAttribute("stroke", DARK ? "#4f5fa8" : "#94a3b8")
        rule.setAttribute("stroke-width", "2")
        rule.setAttribute("stroke-dasharray", "6 6")
        svg.appendChild(rule)
        const tag = el("div", { class: "ll alt-else" }, `${icon("corner-down-right")}${divider.label}`)
        tag.style.left = `${left + 18}px`
        tag.style.top = `${divider.y - 13}px`
        art.appendChild(tag)
      })
    } else if (item.kind === "self") {
      const at = x[item.self]
      line(svg, [[at + 6, item.y - 12], [at + 56, item.y - 12], [at + 56, item.y + 14], [at + 8, item.y + 14]])
      const msg = el("div", { class: "msg self" }, item.text)
      msg.style.left = `${at + 68}px`
      msg.style.top = `${item.y + 1}px`
      art.appendChild(msg)
      const badge = el("div", { class: `badge tone-${tone(item.self)}` }, String(item.number))
      badge.style.left = `${at - 22}px`
      badge.style.top = `${item.y - 12}px`
      art.appendChild(badge)
    } else if (item.kind === "note") {
      const note = el("div", { class: "note" }, item.note)
      note.style.top = `${item.y}px`
      art.appendChild(note)
      const half = note.offsetWidth / 2
      note.style.left = `${Math.min(Math.max(x[item.over], half + 12), width - half - 12)}px`
    } else {
      const from = x[item.from]
      const to = x[item.to]
      const dir = Math.sign(to - from)
      line(svg, [[from + dir * 6, item.y], [to - dir * 4, item.y]], { dashed: item.reply, soft: item.reply })
      const msg = el("div", { class: `msg${item.reply ? " reply" : ""}` }, item.text)
      msg.style.left = `${(from + to) / 2 + dir * 14}px`
      msg.style.top = `${item.y - 2}px`
      art.appendChild(msg)
      const badge = el("div", { class: `badge tone-${tone(item.from)}` }, String(item.number))
      badge.style.left = `${from + dir * 22}px`
      badge.style.top = `${item.y - 20}px`
      art.appendChild(badge)
    }
  })
}

// Graph: nodes on a grid (col, row), edges drawn between box sides with optional labels.
// nodes: { id, label, sub, icon, tone, col, row, w } | { id, start: true, col, row } | { id, end: true, col, row }
// edges: { from, to, label, dashed, via: [[x, y]], fromSide, toSide, labelAt: [dx, dy] }
// groups: { label, tone, nodes: [ids] }
function graph(art, { nodes, edges, groups = [], colWidth = 300, rowHeight = 150, nodeWidth = 250, width, height }) {
  const pad = 40
  const boxes = {}
  nodes.forEach((n) => {
    const w = n.start || n.end ? 22 : (n.w || nodeWidth)
    const left = pad + n.col * colWidth + (colWidth - w) / 2
    const top = pad + n.row * rowHeight
    const node = n.start || n.end
      ? el("div", { class: n.end ? "start end" : "start" })
      : el("div", { class: `node tone-${n.tone || "blue"}${n.icon ? "" : " center"}` },
        `${icon(n.icon)}<div><div class="t">${n.label}</div>${n.sub ? `<div class="s">${n.sub}</div>` : ""}</div>`)
    node.style.left = `${left}px`
    node.style.top = `${top}px`
    if (!n.start && !n.end) node.style.width = `${w}px`
    art.appendChild(node)
    boxes[n.id] = node
  })

  lucide.createIcons()
  const rect = (id) => {
    const b = boxes[id]
    return { x: b.offsetLeft, y: b.offsetTop, w: b.offsetWidth, h: b.offsetHeight }
  }

  groups.forEach((g) => {
    const rs = g.nodes.map(rect)
    const left = Math.min(...rs.map((r) => r.x)) - 24
    const top = Math.min(...rs.map((r) => r.y)) - 30
    const right = Math.max(...rs.map((r) => r.x + r.w)) + 24
    const bottom = Math.max(...rs.map((r) => r.y + r.h)) + 24
    const box = el("div", { class: `group tone-${g.tone || "gray"}` }, `<div class="gl">${g.label}</div>`)
    Object.assign(box.style, { left: `${left}px`, top: `${top}px`, width: `${right - left}px`, height: `${bottom - top}px` })
    art.insertBefore(box, art.firstChild)
  })

  const all = Object.keys(boxes).map(rect)
  const w = width || Math.max(...all.map((r) => r.x + r.w)) + pad + 24
  const h = height || Math.max(...all.map((r) => r.y + r.h)) + pad + 24
  art.style.width = `${w}px`
  art.style.height = `${h}px`
  const svg = overlay(art, w, h)

  const side = (r, s) => ({
    left: [r.x, r.y + r.h / 2], right: [r.x + r.w, r.y + r.h / 2],
    top: [r.x + r.w / 2, r.y], bottom: [r.x + r.w / 2, r.y + r.h]
  })[s]

  edges.forEach((e) => {
    const a = rect(e.from)
    const b = rect(e.to)
    const dx = (b.x + b.w / 2) - (a.x + a.w / 2)
    const dy = (b.y + b.h / 2) - (a.y + a.h / 2)
    const horizontal = Math.abs(dx) >= Math.abs(dy)
    const fromSide = e.fromSide || (horizontal ? (dx > 0 ? "right" : "left") : (dy > 0 ? "bottom" : "top"))
    const toSide = e.toSide || (horizontal ? (dx > 0 ? "left" : "right") : (dy > 0 ? "top" : "bottom"))
    let start = side(a, fromSide)
    let end = side(b, toSide)
    if (e.offset) {
      const [ox, oy] = horizontal ? [0, e.offset] : [e.offset, 0]
      start = [start[0] + ox, start[1] + oy]
      end = [end[0] + ox, end[1] + oy]
    }
    const points = [start, ...(e.via || []), end]
    line(svg, points, { dashed: e.dashed, soft: e.dashed })
    if (e.label) {
      const mid = e.via?.length ? e.via[Math.floor((e.via.length - 1) / 2)] : [(start[0] + end[0]) / 2, (start[1] + end[1]) / 2]
      const [lx, ly] = e.labelAt || [0, 0]
      const label = el("div", { class: "label" }, e.label)
      label.style.left = `${mid[0] + lx}px`
      label.style.top = `${mid[1] + ly}px`
      art.appendChild(label)
    }
  })
}

// Timeline: dated milestones along a horizontal axis.
// items: { date, text, tone, icon }
function timeline(art, { items, width = 1100 }) {
  const pad = 60
  const step = (width - pad * 2) / items.length
  art.style.width = `${width}px`
  const axisY = 70
  let height = 0
  items.forEach((item, i) => {
    const cx = pad + step * i + step / 2
    const dot = el("div", { class: `tl-dot tone-${item.tone || "blue"}` }, icon(item.icon || "calendar"))
    dot.style.left = `${cx}px`
    dot.style.top = `${axisY}px`
    art.appendChild(dot)
    const card = el("div", { class: `tl-card tone-${item.tone || "blue"}` }, `<div class="t">${item.date}</div><div class="s">${item.text}</div>`)
    card.style.left = `${cx - step / 2 + 10}px`
    card.style.width = `${step - 20}px`
    card.style.top = `${axisY + 46}px`
    art.appendChild(card)
    height = Math.max(height, axisY + 46 + card.offsetHeight + 40)
  })
  art.style.height = `${height}px`
  const svg = overlay(art, width, height)
  const axis = document.createElementNS(SVG_NS, "path")
  axis.setAttribute("d", `M${pad},${axisY} H${width - pad}`)
  axis.setAttribute("stroke", DARK ? "#334155" : "#cbd5e1")
  axis.setAttribute("stroke-width", "3")
  svg.appendChild(axis)
  art.appendChild(svg)
  art.querySelectorAll(".tl-dot").forEach((dot) => art.appendChild(dot))
}

function render(id, kind, spec) {
  let art = document.getElementById(id)
  if (!art) {
    art = el("div", { class: "art", id })
    document.body.appendChild(art)
  }
  if (kind === "sequence") sequence(art, spec)
  if (kind === "graph") graph(art, spec)
  if (kind === "timeline") timeline(art, spec)
  lucide.createIcons()
}
