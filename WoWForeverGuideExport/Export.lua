-- WoW Forever Guide - Exportar personaje.
-- Escribe /wfg: sale una ventana con una sola línea de texto ya seleccionada. Cópiala (Ctrl+C) y pégala en la
-- app, en «Importar personaje». El addon solo MUESTRA el texto: no envía nada a ningún sitio.
--
-- Formato:  !WFG:1:{json}
--   v = versión del formato      n = nombre        r = reino
--   f = "A" (Alianza) o "H" (Horda)   c = clase (WARRIOR, MAGE...)   l = nivel
--   p = profesiones [{i = número de habilidad, n = nombre, l = nivel}]
--   pvp = {rank = rango 1-14, honor = honor}   (solo si el juego lo da)
--   ra = raza (clave en inglés: "Human", "NightElf"...)   sx = sexo ("M" hombre o "F" mujer)
--   g = equipo [{s = casilla 1-19, i = id del objeto, n = nombre, e = id del encantamiento, q = calidad 0-8, l = nivel,
--                ic = nombre del icono, en = texto del encantamiento, d = líneas de la descripción ["g|texto", ...]}]
--        (en d, la letra antes de | es el color: n normal, g verde, r rojo, y amarillo, x gris; \t separa izquierda y derecha)
--   st = estadísticas {str, agi, sta, int, spi, armor, hp, power, power_type, ap, sp, heal, crit, rcrit, scrit, dodge, parry, block, resil}
--   t = talentos de la rama 1 (o los únicos) [{n = nombre del árbol, p = puntos, t = [{n = nombre, r = rango, m = rango máximo,
--        f = fila, c = columna, ic = icono, rq = [[fila, columna]...], d = descripción ["g|texto"...]}]}] (con todos los talentos del árbol, también los de 0 puntos)
--   t2 = talentos de la rama 2 (solo con doble especialización)   ta = rama activa (1 o 2)
--   x = extras opcionales (hermandad, dinero, monedas, reputaciones, habilidades, hechizos, experiencia, bolsas, banco,
--        PvP, logros, monturas, mascotas, tiempo jugado, zona): ver la sección «extras» más abajo
-- Todo lo que el juego no dé se omite: nunca se inventa nada.

local ADDON, ns = ...
ns = ns or {}

local VERSION_FORMATO = 1
local VERSION_ADDON = "1.9.9" -- la misma que en el .toc: es la que dice /wfgversion
local PREFIJO = "!WFG:" .. VERSION_FORMATO .. ":"

-- Llama a una función del juego sin que un fallo rompa el addon (si no existe o falla, devuelve nil).
local function intentar(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(f, ...)
  if ok then return a, b, c, d end
  return nil
end

-- ------------------------------------------------------------------ JSON mínimo

local function texto_json(s)
  s = tostring(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("%c", function(c) return string.format("\\u%04x", string.byte(c)) end)
  return '"' .. s .. '"'
end

local function a_json(v)
  local t = type(v)
  if t == "string" then
    return texto_json(v)
  elseif t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.2f", v)
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "table" then
    if next(v) == nil or #v > 0 then
      local partes = {}
      for i, x in ipairs(v) do partes[i] = a_json(x) end
      return "[" .. table.concat(partes, ",") .. "]"
    end
    local claves = {}
    for k in pairs(v) do claves[#claves + 1] = k end
    table.sort(claves)
    local partes = {}
    for _, k in ipairs(claves) do partes[#partes + 1] = texto_json(k) .. ":" .. a_json(v[k]) end
    return "{" .. table.concat(partes, ",") .. "}"
  end
  return "null"
end

-- ------------------------------------------------------------------ profesiones

-- Número de habilidad de cada profesión (el mismo en todos los idiomas) y sus nombres por si el juego no lo da.
local HABILIDADES = {
  [171] = true, [164] = true, [333] = true, [202] = true, [182] = true, [165] = true,
  [186] = true, [393] = true, [197] = true, [185] = true, [356] = true, [129] = true,
}
local POR_NOMBRE = {
  ["Alchemy"] = 171, ["Alquimia"] = 171,
  ["Blacksmithing"] = 164, ["Herrería"] = 164,
  ["Enchanting"] = 333, ["Encantamiento"] = 333,
  ["Engineering"] = 202, ["Ingeniería"] = 202,
  ["Herbalism"] = 182, ["Herboristería"] = 182,
  ["Leatherworking"] = 165, ["Peletería"] = 165,
  ["Mining"] = 186, ["Minería"] = 186,
  ["Skinning"] = 393, ["Desuello"] = 393,
  ["Tailoring"] = 197, ["Sastrería"] = 197,
  ["Cooking"] = 185, ["Cocina"] = 185,
  ["Fishing"] = 356, ["Pesca"] = 356,
  ["First Aid"] = 129, ["Primeros auxilios"] = 129,
}

local function profesiones()
  local salida, vistas = {}, {}
  local function anadir(nombre, habilidad, nivel)
    if not nombre or not nivel or nivel <= 0 then return end
    local id = (habilidad and HABILIDADES[habilidad]) and habilidad or POR_NOMBRE[nombre]
    if not id or vistas[id] then return end
    vistas[id] = true
    salida[#salida + 1] = { i = id, n = nombre, l = nivel }
  end

  -- Cliente actual: GetProfessions devuelve los índices (primarias, arqueología, pesca y cocina).
  if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
    local ok, p1, p2, p3, p4, p5 = pcall(GetProfessions)
    if ok then
      for _, indice in ipairs({ p1 or false, p2 or false, p3 or false, p4 or false, p5 or false }) do
        if indice then
          local ok2, nombre, _, nivel, _, _, _, habilidad = pcall(GetProfessionInfo, indice)
          if ok2 then anadir(nombre, habilidad, nivel) end
        end
      end
    end
  end

  -- Cliente clásico: lista de habilidades. Se quedan solo las profesiones conocidas, por nombre.
  if #salida == 0 and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
    local ok, total = pcall(GetNumSkillLines)
    if ok and total then
      for i = 1, total do
        local ok2, nombre, cabecera, _, nivel = pcall(GetSkillLineInfo, i)
        if ok2 and nombre and not cabecera then anadir(nombre, nil, nivel) end
      end
    end
  end

  table.sort(salida, function(a, b) return a.i < b.i end)
  return salida
end

-- ------------------------------------------------------------------ PvP

-- Solo se incluye lo que el juego da de verdad. El rango en el cliente clásico va de 5 a 18 (rango 1 a 14).
local function pvp()
  local r = {}
  local bruto = intentar(UnitPVPRank, "player")
  if type(bruto) == "number" and bruto >= 5 and bruto <= 18 then r.rank = bruto - 4 end
  -- Honor: según el cliente viene de una función clásica, de la moneda «Honor» o de UnitHonor. Un 0 también cuenta.
  local honor = intentar(GetHonorCurrency)
  -- UnitHonor NO sirve aquí: en este cliente es el progreso dentro del nivel de honor, no el honor total.
  if type(honor) ~= "number" and C_CurrencyInfo then
    for _, id in ipairs({ 1901, 392 }) do
      local c = intentar(C_CurrencyInfo.GetCurrencyInfo, id)
      if type(c) == "table" and type(c.quantity) == "number" then honor = c.quantity; break end
    end
  end
  if type(honor) ~= "number" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
    local total = intentar(C_CurrencyInfo.GetCurrencyListSize)
    for i = 1, type(total) == "number" and total or 0 do
      local c = intentar(C_CurrencyInfo.GetCurrencyListInfo, i)
      if type(c) == "table" and type(c.name) == "string" and (c.name:lower():find("honor") or c.name:lower():find("honra"))
          and type(c.quantity) == "number" then honor = c.quantity; break end
    end
  end
  if type(honor) == "number" and honor >= 0 then r.honor = honor end
  return r
end


-- Búsqueda del rango PvP: el cliente no da UnitPVPRank, así que se buscan funciones con «rank»/«honor» en el nombre.
-- Solo se LLAMAN las que empiezan por Get o Unit (lecturas); del resto solo se anota el nombre.
local function buscar_rango_pvp()
  local nombres, valores = {}, {}
  local function mirar(prefijo, tabla)
    for k, v in pairs(tabla) do
      if type(k) == "string" and type(v) == "function" then
        local m = k:lower()
        if (m:find("rank") and (m:find("pvp") or m:find("honor") or m:find("pk"))) or m:find("honor") then
          local completo = prefijo .. k
          nombres[#nombres + 1] = completo
          if (k:find("^Get") or k:find("^Unit")) and #valores < 12 then
            local ok, a, b, c = pcall(v, "player")
            if ok and a ~= nil then valores[#valores + 1] = completo .. "=" .. tostring(a) .. (b ~= nil and ("," .. tostring(b)) or "") .. (c ~= nil and ("," .. tostring(c)) or "") end
          end
        end
      end
    end
  end
  mirar("", _G)
  for _, t in ipairs({ "C_PvP", "C_PvPRank", "C_HonorInfo", "C_PlayerInfo" }) do
    if type(_G[t]) == "table" then mirar(t .. ".", _G[t]) end
  end
  table.sort(nombres)
  return nombres, valores
end

-- ------------------------------------------------------------------ estadísticas

local function estadisticas()
  local s = {}
  local function poner(clave, valor)
    if type(valor) == "number" and valor == valor and valor > -1e9 and valor < 1e9 then s[clave] = valor end
  end
  local function mayor(f, desde, hasta)
    local m
    for escuela = desde, hasta do
      local v = intentar(f, escuela)
      if type(v) == "number" and (not m or v > m) then m = v end
    end
    return m
  end
  for i, clave in ipairs({ "str", "agi", "sta", "int", "spi" }) do
    local _, efectiva = intentar(UnitStat, "player", i)
    poner(clave, efectiva)
  end
  local _, armadura = intentar(UnitArmor, "player")
  poner("armor", armadura)
  poner("hp", intentar(UnitHealthMax, "player"))
  poner("power", intentar(UnitPowerMax, "player"))
  local _, tipo = intentar(UnitPowerType, "player")
  if type(tipo) == "string" then s.power_type = tipo end
  local base, mas, menos = intentar(UnitAttackPower, "player")
  if type(base) == "number" then poner("ap", base + (mas or 0) + (menos or 0)) end
  poner("sp", mayor(GetSpellBonusDamage, 2, 7))
  poner("heal", intentar(GetSpellBonusHealing))
  poner("crit", intentar(GetCritChance))
  poner("rcrit", intentar(GetRangedCritChance))
  poner("scrit", mayor(GetSpellCritChance, 2, 7))
  poner("dodge", intentar(GetDodgeChance))
  poner("parry", intentar(GetParryChance))
  poner("block", intentar(GetBlockChance))
  if type(GetCombatRating) == "function" and type(CR_RESILIENCE_CRIT_TAKEN) == "number" then
    poner("resil", intentar(GetCombatRating, CR_RESILIENCE_CRIT_TAKEN))
  end
  return s
end

-- ------------------------------------------------------------------ equipo

local function info_objeto(enlace)
  local f = GetItemInfo or (C_Item and C_Item.GetItemInfo)
  -- (nombre, enlace, calidad, nivel...): puede no estar en la caché del juego y entonces no sale.
  local _, _, calidad, nivel = intentar(f, enlace)
  return calidad, nivel
end

local function sin_codigos(t)
  t = t:gsub("|c%x%x%x%x%x%x%x%x", "")
  t = t:gsub("|r", "")
  t = t:gsub("|T.-|t", "")
  t = t:gsub("|H.-|h(.-)|h", "%1")
  return t
end

-- Letra del color de una línea de la descripción: r rojo, g verde, y amarillo, x gris, n normal.
local function marca_color(r, g, b)
  if type(r) ~= "number" then return "n" end
  if r > 0.85 and g < 0.35 then return "r" end
  if g > 0.8 and r < 0.4 and b < 0.4 then return "g" end
  if r > 0.85 and g > 0.7 and b < 0.3 then return "y" end
  if r < 0.65 and g < 0.65 and b < 0.65 then return "x" end
  return "n"
end

local escaner

-- Lee las líneas que el juego enseña al pasar el ratón por algo; `rellenar(tooltip)` lo pone en el tooltip
-- (un objeto, un talento...). Se guardan como mucho `maximo` líneas de cada una, de `largo` letras.
local function descripcion(rellenar, maximo, largo)
  if type(CreateFrame) ~= "function" then return nil end
  if not escaner then
    local ok, marco = pcall(CreateFrame, "GameTooltip", "WFGEscanerTooltip", nil, "GameTooltipTemplate")
    if not ok or not marco then return nil end
    escaner = marco
  end
  local ok = pcall(function()
    escaner:SetOwner(UIParent, "ANCHOR_NONE")
    escaner:ClearLines()
    rellenar(escaner)
  end)
  if not ok then return nil end
  local total = escaner:NumLines() or 0
  local lineas = {}
  -- La línea 1 es el nombre (ya lo tenemos); se guardan como mucho 40 líneas.
  for i = 2, math.min(total, maximo or 40) do
    local izq = _G["WFGEscanerTooltipTextLeft" .. i]
    local der = _G["WFGEscanerTooltipTextRight" .. i]
    local texto = izq and izq:GetText()
    if type(texto) == "string" and texto ~= "" then
      local r, g, b = izq:GetTextColor()
      texto = sin_codigos(texto)
      local derecha = der and der:GetText()
      if type(derecha) == "string" and derecha ~= "" then texto = texto .. "\t" .. sin_codigos(derecha) end
      lineas[#lineas + 1] = marca_color(r, g, b) .. "|" .. texto:sub(1, largo or 160)
    end
  end
  return lineas
end

-- El texto del encantamiento es una línea verde que no es un efecto («Equipar:», «Uso:»...) ni un bonus de set.
local function texto_encantamiento(lineas)
  local disparadores = {}
  for _, clave in ipairs({ "ITEM_SPELL_TRIGGER_ONEQUIP", "ITEM_SPELL_TRIGGER_ONUSE", "ITEM_SPELL_TRIGGER_ONPROC" }) do
    local v = _G[clave]
    if type(v) == "string" and v ~= "" then disparadores[#disparadores + 1] = v end
  end
  local prefijo = type(ENCHANTED_TOOLTIP_LINE) == "string" and ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s") or nil
  local candidato
  for _, linea in ipairs(lineas) do
    local color, texto = linea:match("^(%a)|(.*)$")
    if color == "g" and texto and not texto:find("^%(%d") then
      local efecto = false
      for _, d in ipairs(disparadores) do
        if texto:sub(1, #d) == d then efecto = true end
      end
      if not efecto then
        if prefijo and prefijo ~= "" and texto:sub(1, #prefijo) == prefijo then return texto end
        candidato = candidato or texto
      end
    end
  end
  return candidato
end

-- Icono de un objeto o talento: el juego da el nombre de la textura (texto) o, en clientes modernos, su número.
-- Se manda siempre como texto: el nombre en minúsculas o el número tal cual (la app sabe pedir cada uno).
local function nombre_icono(textura)
  if type(textura) == "number" and textura > 0 then return string.format("%d", textura) end
  if type(textura) == "string" then
    local icono = textura:match("([^\\/]+)$")
    if icono and icono ~= "" then return icono:lower() end
  end
  return nil
end

-- Casillas: 1 cabeza ... 18 a distancia, y también camisa (4) y tabardo (19) para la ficha.
local function equipo()
  local salida = {}
  for casilla = 1, 19 do
    do
      local id = intentar(GetInventoryItemID, "player", casilla)
      if type(id) == "number" and id > 0 then
        local objeto = { s = casilla, i = id }
        local textura = intentar(GetInventoryItemTexture, "player", casilla)
        local icono = nombre_icono(textura)
        if not icono and type(GetItemIcon) == "function" then icono = nombre_icono(intentar(GetItemIcon, id)) end
        if icono then objeto.ic = icono end
        local lineas = descripcion(function(t) t:SetInventoryItem("player", casilla) end)
        if lineas and #lineas > 0 then objeto.d = lineas end
        local actual, maxima = intentar(GetInventoryItemDurability, "player", casilla)
        if type(actual) == "number" and type(maxima) == "number" and maxima > 0 then objeto.du = { math.floor(actual), math.floor(maxima) } end
        local enlace = intentar(GetInventoryItemLink, "player", casilla)
        if type(enlace) == "string" then
          -- |cff...|Hitem:ID:ENCANTAMIENTO:...|h[Nombre]|h|r
          local nombre = enlace:match("%[(.-)%]")
          if nombre and nombre ~= "" then objeto.n = nombre end
          local encantamiento = tonumber(enlace:match("item:%d+:(%d*)"))
          if encantamiento and encantamiento > 0 then objeto.e = encantamiento end
          local calidad, nivel = info_objeto(enlace)
          if type(calidad) == "number" and calidad >= 0 and calidad <= 8 then objeto.q = calidad end
          if type(nivel) == "number" and nivel > 0 then objeto.l = nivel end
          if objeto.e and lineas then
            local texto = texto_encantamiento(lineas)
            if texto then objeto.en = texto end
          end
        end
        salida[#salida + 1] = objeto
      end
    end
  end
  return salida
end

-- ------------------------------------------------------------------ talentos

local function nombre_hechizo(id)
  local nombre = intentar(C_Spell and C_Spell.GetSpellName, id)
  if type(nombre) ~= "string" then nombre = intentar(GetSpellInfo, id) end
  return type(nombre) == "string" and nombre or nil
end

-- Forma clásica: pestañas de talentos. Según la versión del cliente, la primera respuesta es el nombre o un número
-- (id) seguido del nombre; se acepta cualquiera de las dos.
local function talentos_clasicos(grupo)
  local arboles = {}
  if not (type(GetNumTalentTabs) == "function" and type(GetTalentTabInfo) == "function"
      and type(GetNumTalents) == "function" and type(GetTalentInfo) == "function") then
    return arboles
  end
  local ok, pestanas = pcall(GetNumTalentTabs)
  if not ok or type(pestanas) ~= "number" then return arboles end
  for pestana = 1, pestanas do
    local ok2, a, b, c, d, e
    if grupo then ok2, a, b, c, d, e = pcall(GetTalentTabInfo, pestana, false, false, grupo)
    else ok2, a, b, c, d, e = pcall(GetTalentTabInfo, pestana) end
    if ok2 then
      local nombre, puntos
      if type(a) == "number" and type(b) == "string" then nombre, puntos = b, e else nombre, puntos = a, c end
      local arbol = { n = tostring(nombre or ("Árbol " .. pestana)), p = tonumber(puntos) or 0, t = {} }
      local ok3, cuantos = pcall(GetNumTalents, pestana)
      if ok3 and type(cuantos) == "number" then
        for i = 1, cuantos do
          local ok4, t1, t2, t3, t4, t5, t6, t7
          if grupo then ok4, t1, t2, t3, t4, t5, t6, t7 = pcall(GetTalentInfo, pestana, i, false, false, grupo)
          else ok4, t1, t2, t3, t4, t5, t6, t7 = pcall(GetTalentInfo, pestana, i) end
          if ok4 then
            local tn, textura, fila, columna, rango, maximo
            if type(t1) == "number" and type(t2) == "string" then
              tn, textura, fila, columna, rango, maximo = t2, t3, t4, t5, t6, t7
            else
              tn, textura, fila, columna, rango, maximo = t1, t2, t3, t4, t5, t6
            end
            if type(tn) == "string" and type(rango) == "number" and #arbol.t < 70 then
              local talento = { n = tn, r = rango, m = type(maximo) == "number" and maximo or nil }
              local posicion = type(fila) == "number" and type(columna) == "number"
              if posicion then talento.f, talento.c = fila, columna end
              local icono = nombre_icono(textura)
              if icono then talento.ic = icono end
              -- De qué talentos depende (las flechas del árbol): ternas fila, columna, aprendible.
              if posicion and type(GetTalentPrereqs) == "function" then
                local req = { pcall(GetTalentPrereqs, pestana, i) }
                if req[1] then
                  local lista = {}
                  for k = 2, #req, 3 do
                    if type(req[k]) == "number" and type(req[k + 1]) == "number" and #lista < 4 then
                      lista[#lista + 1] = { req[k], req[k + 1] }
                    end
                  end
                  if #lista > 0 then talento.rq = lista end
                end
              end
              -- Lo que enseña el juego al pasar el ratón por el talento (descripción del rango actual y del siguiente).
              if posicion then
                local d = descripcion(function(t)
                  if grupo then t:SetTalent(pestana, i, false, false, grupo) else t:SetTalent(pestana, i) end
                end, 8, 250)
                if d and #d > 0 then talento.d = d end
              end
              -- Con posición salen todos (también los de 0 puntos, para dibujar el árbol); sin ella, solo los que tienen puntos.
              if rango > 0 or posicion then arbol.t[#arbol.t + 1] = talento end
            end
          end
        end
      end
      arboles[#arboles + 1] = arbol
    end
  end
  return arboles
end

-- Forma moderna: C_Traits (es lo que usan los exportadores de simuladores en Forever). Salen TODOS los talentos del
-- árbol (también los de 0 puntos) con su posición (fila/columna), icono, descripción y de quién dependen (flechas).
-- El nombre del árbol se pide al juego; si no lo da, sale «Árbol 1», «Árbol 2»...
local function agrupar(valores, maximo, huecos)
  -- Convierte posiciones del juego (números sueltos) en 1..maximo: valores distintos ordenados, o por tramos si son demasiados.
  local lista, visto = {}, {}
  for _, v in ipairs(valores) do
    if not visto[v] then visto[v] = true; lista[#lista + 1] = v end
  end
  table.sort(lista)
  local mapa = {}
  if #lista <= maximo then
    for i, v in ipairs(lista) do mapa[v] = i end
  else
    local minimo, tope = lista[1], lista[#lista]
    for _, v in ipairs(lista) do
      local n = tope > minimo and math.floor((v - minimo) / (tope - minimo) * (huecos - 1) + 0.5) + 1 or 1
      mapa[v] = math.max(1, math.min(maximo, n))
    end
  end
  return mapa
end

-- El juego puede mandar las tres ramas de talentos dentro de un solo árbol, una al lado de otra (o una debajo de otra).
-- Parte los valores de una posición en `partes` grupos: por los huecos más grandes entre ellos o, si están
-- todos a la misma distancia, a partes iguales. Devuelve valor -> grupo (1..partes), o nil si no se ve esa división.
local function trocear(valores, partes)
  local distintos, visto = {}, {}
  for _, v in ipairs(valores) do
    if not visto[v] then visto[v] = true; distintos[#distintos + 1] = v end
  end
  table.sort(distintos)
  local n = #distintos
  if n < partes * 3 then return nil end
  local huecos, ordenados = {}, {}
  for i = 1, n - 1 do
    huecos[i] = { distintos[i + 1] - distintos[i], i }
    ordenados[i] = huecos[i]
  end
  table.sort(ordenados, function(a, b) return a[1] > b[1] end)
  local medio = {}
  for i, h in ipairs(huecos) do medio[i] = h[1] end
  table.sort(medio)
  local mediana = medio[math.ceil(#medio / 2)]
  local cortes = {}
  for k = 1, partes - 1 do
    if ordenados[k][1] > mediana * 1.4 then cortes[#cortes + 1] = ordenados[k][2] end
  end
  if #cortes ~= partes - 1 then
    if n % partes ~= 0 then return nil end
    cortes = {}
    for k = 1, partes - 1 do cortes[k] = math.floor(k * n / partes) end
  end
  table.sort(cortes)
  local grupo = {}
  for i, v in ipairs(distintos) do
    local g = 1
    for _, c in ipairs(cortes) do if i > c then g = g + 1 end end
    grupo[v] = g
  end
  return grupo
end

local function talentos_modernos()
  local arboles = {}
  if not (C_Traits and C_ClassTalents) then return arboles end
  local config = intentar(C_ClassTalents.GetActiveConfigID)
  if not config then return arboles end
  local info = intentar(C_Traits.GetConfigInfo, config)
  if type(info) ~= "table" or type(info.treeIDs) ~= "table" then return arboles end
  for numero, arbolID in ipairs(info.treeIDs) do
    local arbol = { n = "Árbol " .. numero, p = 0, t = {} }
    local datosArbol = C_Traits.GetTreeInfo and intentar(C_Traits.GetTreeInfo, config, arbolID)
    if type(datosArbol) == "table" then
      local nombreArbol = datosArbol.name or datosArbol.treeName or datosArbol.title
      if type(nombreArbol) == "string" and nombreArbol ~= "" then arbol.n = nombreArbol end
    end
    local nodos = intentar(C_Traits.GetTreeNodes, arbolID)
    local lista, xs, ys = {}, {}, {}
    for _, nodoID in ipairs(type(nodos) == "table" and nodos or {}) do
      local nodo = intentar(C_Traits.GetNodeInfo, config, nodoID)
      if type(nodo) == "table" then
        local rango = type(nodo.activeRank) == "number" and nodo.activeRank or 0
        local x, y = tonumber(nodo.posX), tonumber(nodo.posY)
        lista[#lista + 1] = { id = nodoID, nodo = nodo, rango = rango, x = x, y = y }
        if x and y then xs[#xs + 1] = x; ys[#ys + 1] = y end
        arbol.p = arbol.p + rango
      end
    end
    -- ¿Hay varias ramas dentro de este árbol? Se buscan primero por columnas y, si no, por filas.
    local porX = #xs >= 9 and trocear(xs, 3) or nil
    local porY = (not porX) and #ys >= 9 and trocear(ys, 3) or nil
    local grupoDe, ngrupos = {}, 1
    if porX or porY then
      ngrupos = 3
      for _, n in ipairs(lista) do
        if n.x and n.y then grupoDe[n.id] = (porX and porX[n.x]) or (porY and porY[n.y]) or 1 end
      end
    end
    -- Posición (fila, columna) dentro de su rama: cada rama se ajusta a su propia cuadrícula.
    local posicion = {}
    for g = 1, ngrupos do
      local gx, gy = {}, {}
      for _, n in ipairs(lista) do
        if n.x and n.y and (grupoDe[n.id] or 1) == g then gx[#gx + 1] = n.x; gy[#gy + 1] = n.y end
      end
      local colDe = #gx > 0 and agrupar(gx, 6, 4) or {}
      local filaDe = #gy > 0 and agrupar(gy, 12, 7) or {}
      for _, n in ipairs(lista) do
        if n.x and n.y and (grupoDe[n.id] or 1) == g and colDe[n.x] and filaDe[n.y] then posicion[n.id] = { filaDe[n.y], colDe[n.x] } end
      end
    end
    local ramas = {}
    for g = 1, ngrupos do
      ramas[g] = { n = ngrupos > 1 and ("Árbol " .. g) or arbol.n, p = 0, t = {} }
      if ngrupos > 1 and type(GetSpecializationInfo) == "function" then
        local ok, _, nombre = pcall(GetSpecializationInfo, g)
        if ok and type(nombre) == "string" and nombre ~= "" then ramas[g].n = nombre end
      end
    end
    for _, n in ipairs(lista) do ramas[grupoDe[n.id] or 1].p = ramas[grupoDe[n.id] or 1].p + n.rango end
    -- Flechas: cada nodo dice a qué nodos lleva; al revés, cada nodo depende de los que llevan a él.
    local requisitos = {}
    for _, n in ipairs(lista) do
      for _, borde in ipairs(type(n.nodo.visibleEdges) == "table" and n.nodo.visibleEdges or {}) do
        local destino = type(borde) == "table" and borde.targetNode
        if destino and posicion[n.id] then
          requisitos[destino] = requisitos[destino] or {}
          table.insert(requisitos[destino], posicion[n.id])
        end
      end
    end
    for _, n in ipairs(lista) do
      local nodo = n.nodo
      local rama = ramas[grupoDe[n.id] or 1]
      if #rama.t < 70 and (n.rango > 0 or posicion[n.id]) then
        local entrada = (type(nodo.activeEntry) == "table" and nodo.activeEntry.entryID)
          or (type(nodo.entryIDs) == "table" and nodo.entryIDs[1])
        local e = entrada and intentar(C_Traits.GetEntryInfo, config, entrada)
        local def = type(e) == "table" and e.definitionID and intentar(C_Traits.GetDefinitionInfo, e.definitionID)
        local hechizo = type(def) == "table" and def.spellID or nil
        local nombre = type(def) == "table" and (def.overrideName or (hechizo and nombre_hechizo(hechizo))) or nil
        local talento = {
          n = type(nombre) == "string" and nombre or ("Talento " .. n.id),
          r = n.rango,
          m = type(nodo.maxRanks) == "number" and nodo.maxRanks or nil,
        }
        if posicion[n.id] then talento.f, talento.c = posicion[n.id][1], posicion[n.id][2] end
        local textura = type(def) == "table" and def.overrideIcon or nil
        if not textura and hechizo then
          textura = intentar(C_Spell and C_Spell.GetSpellTexture, hechizo)
          if not textura and type(GetSpellTexture) == "function" then textura = intentar(GetSpellTexture, hechizo) end
        end
        local icono = nombre_icono(textura)
        if icono then talento.ic = icono end
        if requisitos[n.id] then
          local rq = {}
          for _, q in ipairs(requisitos[n.id]) do
            if #rq < 4 then rq[#rq + 1] = { q[1], q[2] } end
          end
          if #rq > 0 then talento.rq = rq end
        end
        if hechizo then
          local texto = intentar(C_Spell and C_Spell.GetSpellDescription, hechizo)
          if type(texto) ~= "string" and type(GetSpellDescription) == "function" then
            texto = intentar(GetSpellDescription, hechizo)
          end
          if type(texto) == "string" and texto ~= "" then
            texto = sin_codigos(texto)
            if #texto > 250 then texto = texto:sub(1, 250) end
            talento.d = { "g|" .. texto }
          end
        end
        rama.t[#rama.t + 1] = talento
      end
    end
    for g = 1, ngrupos do arboles[#arboles + 1] = ramas[g] end
  end
  return arboles
end

-- Sin puntos gastados solo vale si se leyó la forma del árbol (talentos con su fila y columna): así se ven los
-- árboles aunque estén vacíos. Sin forma ni puntos es que no se leyó nada útil.
local function con_puntos(arboles)
  local total = 0
  for _, a in ipairs(arboles) do
    total = total + (a.p or 0)
    for _, y in ipairs(a.t or {}) do
      if y.f then total = total + 1 end
    end
  end
  return total > 0 and arboles or {}
end

-- Devuelve los talentos de la rama 1, los de la rama 2 (solo con doble especialización) y cuál está activa.
local function talentos()
  local grupos = intentar(GetNumTalentGroups)
  if type(grupos) == "number" and grupos >= 2 then
    local uno, dos = con_puntos(talentos_clasicos(1)), con_puntos(talentos_clasicos(2))
    if #uno > 0 or #dos > 0 then
      local activa = intentar(GetActiveTalentGroup)
      return uno, dos, (activa == 1 or activa == 2) and activa or nil
    end
  end
  local arboles = con_puntos(talentos_clasicos())
  if #arboles > 0 then return arboles, {}, nil end
  arboles = con_puntos(talentos_modernos())
  if #arboles == 0 then return arboles, {}, nil end
  -- Forever tiene doble especialización y este cliente solo da la configuración activa. La segunda rama sale con la
  -- misma forma de árbol y sin puntos (vacía): si el jugador no ha gastado nada en ella es exactamente eso.
  local vacia = {}
  for i, a in ipairs(arboles) do
    local copia = { n = a.n, p = 0, t = {} }
    for j, y in ipairs(a.t) do
      local c = {}
      for k, v in pairs(y) do c[k] = v end
      c.r = 0
      copia.t[j] = c
    end
    vacia[i] = copia
  end
  return arboles, vacia, 1
end

-- ------------------------------------------------------------------ extras (x)
-- Todo opcional y a prueba de fallos: lo que el cliente no dé, no sale. Claves compactas dentro de x:
--   gu = {n, rk, m}  hermandad: nombre, rango, mensaje del día        mo = dinero en cobres
--   mn = [{n, q, ic}] monedas (honor, marcas...)                      rp = [{n, s = nivel 1-8, v = puntos, m = máximo}]
--   sk = [{n, r, m}] habilidades (armas, defensa, idiomas...)         sp = [{n, s = ["Hechizo|Rango", ...]}] libro de hechizos
--   xp = {a = actual, m = para subir, d = descansado}                 bg = bolsas [{i, c, n, ic}]   bk = banco (solo si se abrió)
--   pv = {hl = nivel de honor, hx = progreso, hm = máximo del nivel, hk, dk, hoy = {hk, ph}, ayer = {hk, dk, ph}, sem = {hk, ph}, ant = {hk, dk, ph, rk}}  estadísticas PvP
--   lg = {pt = puntos, l = [{i, n, p, d = "AAAA-MM-DD"}]}  logros     mt = [nombres] monturas      mc = [nombres] mascotas
--   tj = segundos jugados     zn = zona   sz = subzona

local desempaquetar = table.unpack or unpack

local function llamar(f, ...)
  if type(f) ~= "function" then return {} end
  -- Se recogen los resultados tal cual: un hueco en medio (p. ej. «expandido» vacío en las filas de habilidades) no
  -- debe cortar los que vienen detrás, y con `#` sobre una lista con huecos se perderían.
  local function recoger(ok, ...)
    if not ok then return {} end
    return { ... }
  end
  return recoger(pcall(f, ...))
end

local function numero(v) return type(v) == "number" and v == v and v or nil end

local tiempo_jugado
do
  local suprimir = false
  if type(ChatFrame_DisplayTimePlayed) == "function" then
    local original = ChatFrame_DisplayTimePlayed
    ChatFrame_DisplayTimePlayed = function(...)
      if suprimir then return end
      return original(...)
    end
  end
  if type(CreateFrame) == "function" then
    local marco = CreateFrame("Frame")
    pcall(function() marco:RegisterEvent("TIME_PLAYED_MSG") end)
    marco:SetScript("OnEvent", function(_, evento, total)
      if evento == "TIME_PLAYED_MSG" and type(total) == "number" then tiempo_jugado = total end
    end)
  end
  function ns.PedirTiempo()
    suprimir = true
    intentar(RequestTimePlayed)
    if C_Timer and C_Timer.After then C_Timer.After(3, function() suprimir = false end) else suprimir = false end
  end
end

-- Banco de hermandad: solo se lee con su ventana abierta, así que se guarda lo último visto (en el archivo del addon).
local banco_hermandad
local function recordar_banco_hermandad()
  local b = {}
  local dinero = numero(intentar(GetGuildBankMoney))
  if dinero then b.m = dinero end
  local total = numero(intentar(GetNumGuildBankTabs)) or 0
  for i = 1, math.min(total, 8) do
    local nombre = intentar(GetGuildBankTabInfo, i)
    if type(nombre) == "string" and nombre ~= "" then
      b.t = b.t or {}
      b.t[#b.t + 1] = nombre:sub(1, 30)
    end
  end
  if next(b) == nil then return end
  banco_hermandad = b
  WFGExportDB = WFGExportDB or {}
  WFGExportDB.banco_hermandad = b
end

-- La lista de miembros llega del servidor del juego con un pequeño retraso: se pide al entrar y al exportar.
local function pedir_hermandad()
  if type(IsInGuild) == "function" and not intentar(IsInGuild) then return end
  intentar(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster)
end

local function x_hermandad()
  local r = llamar(GetGuildInfo, "player")
  if type(r[1]) ~= "string" then return nil end
  local g = { n = r[1] }
  if type(r[2]) == "string" then g.rk = r[2] end
  if numero(r[3]) then g.ri = r[3] end -- 0 = Maestro de hermandad
  local m = intentar(GetGuildRosterMOTD)
  if type(m) == "string" and m ~= "" then g.m = m:sub(1, 200) end
  local info = intentar(GetGuildInfoText)
  if type(info) == "string" and info ~= "" then g.t = info:sub(1, 500) end
  -- Jerarquía: nombre de cada rango, del 1.º (Maestro) hacia abajo.
  local rangos = {}
  local total_rangos = numero(intentar(GuildControlGetNumRanks)) or 0
  for i = 1, math.min(total_rangos, 10) do
    local nombre = intentar(GuildControlGetRankName, i)
    if type(nombre) == "string" and nombre ~= "" then rangos[i] = nombre:sub(1, 30) else rangos[i] = "?" end
  end
  if #rangos > 0 then g.rl = rangos end
  -- Lista de miembros (la primera vez puede salir vacía hasta que el juego la envía).
  local total, conectados = 0, 0
  local a, b = intentar(GetNumGuildMembers)
  if numero(a) then total = a end
  if numero(b) then conectados = b end
  if total > 0 then
    g.nm = total
    g.on = conectados
    local lista = {}
    for i = 1, math.min(total, 500) do
      local f = llamar(GetGuildRosterInfo, i)
      -- nombre, rango, índice de rango, nivel, clase (en tu idioma), zona, nota, nota de oficial, conectado, estado, clase (clave)
      local nombre = type(f[1]) == "string" and f[1]:gsub("%-.*$", "") or nil
      if nombre and nombre ~= "" then
        local m2 = { n = nombre:sub(1, 20) }
        if type(f[11]) == "string" then m2.c = f[11] end
        if numero(f[4]) then m2.l = f[4] end
        if numero(f[3]) then m2.ri = f[3] end
        if f[9] then
          m2.o = 1
          if type(f[6]) == "string" and f[6] ~= "" then m2.z = f[6]:sub(1, 30) end
        else
          local anios, meses, dias, horas = intentar(GetGuildRosterLastOnline, i)
          if numero(anios) then
            m2.h = ((anios * 12 + (meses or 0)) * 30 + (dias or 0)) * 24 + (horas or 0) -- horas desde que se conectó (aprox.)
          end
        end
        lista[#lista + 1] = m2
      end
    end
    if #lista > 0 then g.ro = lista end
    -- Mi nota y la de oficial (solo salen si mi rango puede verlas).
    local yo = intentar(UnitName, "player")
    for i = 1, math.min(total, 500) do
      local f = llamar(GetGuildRosterInfo, i)
      if type(f[1]) == "string" and f[1]:gsub("%-.*$", "") == yo then
        if type(f[7]) == "string" and f[7] ~= "" then g.np = f[7]:sub(1, 60) end
        if type(f[8]) == "string" and f[8] ~= "" then g.no = f[8]:sub(1, 60) end
        break
      end
    end
  end
  if banco_hermandad == nil and type(WFGExportDB) == "table" then banco_hermandad = WFGExportDB.banco_hermandad end
  if banco_hermandad then g.bk = banco_hermandad end
  return g
end

local function x_monedas()
  local salida = {}
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
    local total = numero(intentar(C_CurrencyInfo.GetCurrencyListSize)) or 0
    for i = 1, total do
      local c = intentar(C_CurrencyInfo.GetCurrencyListInfo, i)
      if type(c) == "table" and not c.isHeader and type(c.name) == "string" and type(c.quantity) == "number" and #salida < 30 then
        local m = { n = c.name, q = c.quantity }
        local ic = nombre_icono(c.iconFileID)
        if ic then m.ic = ic end
        salida[#salida + 1] = m
      end
    end
  elseif type(GetCurrencyListSize) == "function" then
    for i = 1, numero(intentar(GetCurrencyListSize)) or 0 do
      local r = llamar(GetCurrencyListInfo, i)
      if type(r[1]) == "string" and not r[2] and type(r[6]) == "number" and #salida < 30 then
        salida[#salida + 1] = { n = r[1], q = r[6], ic = nombre_icono(r[5]) }
      end
    end
  end
  return salida
end

local function x_reputaciones()
  local salida = {}
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    for i = 1, numero(intentar(C_Reputation.GetNumFactions)) or 0 do
      local f = intentar(C_Reputation.GetFactionDataByIndex, i)
      if type(f) == "table" and type(f.name) == "string" and not f.isHeader and #salida < 80 then
        local minimo, maximo, valor = f.currentReactionThreshold or 0, f.nextReactionThreshold or 0, f.currentStanding or 0
        salida[#salida + 1] = { n = f.name, s = f.reaction, v = valor - minimo, m = maximo - minimo }
      end
    end
  elseif type(GetNumFactions) == "function" then
    for i = 1, numero(intentar(GetNumFactions)) or 0 do
      local r = llamar(GetFactionInfo, i)
      -- nombre, descripción, nivel, mínimo, máximo, valor, ..., esCabecera (9)
      if type(r[1]) == "string" and not r[9] and #salida < 80 then
        local minimo, maximo, valor = r[4] or 0, r[5] or 0, r[6] or 0
        salida[#salida + 1] = { n = r[1], s = r[3], v = valor - minimo, m = maximo - minimo }
      end
    end
  end
  return salida
end

-- Las funciones de la lista de habilidades: globales en los clientes clásicos y dentro de C_SkillInfo en los nuevos.
local function api_habilidades()
  local c = C_SkillInfo
  local function elegir(nombre)
    if type(_G[nombre]) == "function" then return _G[nombre] end
    if type(c) == "table" and type(c[nombre]) == "function" then return c[nombre] end
    return nil
  end
  return { num = elegir("GetNumSkillLines"), info = elegir("GetSkillLineInfo"),
           expandir = elegir("ExpandSkillHeader"), plegar = elegir("CollapseSkillHeader"), por_id = elegir("GetSkillLineInfoByID") }
end

-- Una fila de la lista: (nombre, esCabecera, expandida, rango, máximo). Sirve tanto si el juego devuelve valores sueltos
-- (clásico) como si devuelve una tabla (cliente nuevo).
local function fila_habilidad(api, i)
  local r = llamar(api.info, i)
  local t = r[1]
  if type(t) == "table" then
    local function campo(...)
      for _, k in ipairs({ ... }) do if t[k] ~= nil then return t[k] end end
      return nil
    end
    return campo("skillName", "name", "skillLineName"), campo("isHeader", "header") and true or false,
      campo("isExpanded", "expanded"), numero(campo("skillRank", "rank", "skillLevel", "currentRank", "curRank")),
      numero(campo("skillMaxRank", "maxRank", "maxSkillRank", "maxSkillLevel"))
  end
  return r[1], r[2] and true or false, r[3], numero(r[4]), numero(r[7])
end

-- Los encabezados plegados de la lista de habilidades esconden sus filas (ahí están, por ejemplo, la ganzúa y la
-- equitación). Se despliegan todos para leer y luego se vuelven a plegar los que lo estaban, para no cambiar lo que ve el jugador.
local function con_habilidades_desplegadas(api, leer)
  local plegados = {}
  if api.expandir and api.plegar then
    for i = 1, numero(intentar(api.num)) or 0 do
      local nombre, cabecera, expandida = fila_habilidad(api, i)
      if type(nombre) == "string" and cabecera and (expandida == nil or expandida == false or expandida == 0) then plegados[nombre] = true end
    end
    if next(plegados) then pcall(api.expandir, 0) end
  end
  local ok, resultado = pcall(leer)
  ns.errorHabilidades = (not ok) and tostring(resultado) or nil
  if next(plegados) then
    -- De abajo arriba, para que plegar una no cambie el número de las que quedan por encima.
    for i = numero(intentar(api.num)) or 0, 1, -1 do
      local nombre, cabecera = fila_habilidad(api, i)
      if type(nombre) == "string" and cabecera and plegados[nombre] then pcall(api.plegar, i) end
    end
  end
  if ok and type(resultado) == "table" then return resultado end
  return {}
end

local function x_habilidades()
  local api = api_habilidades()
  if not api.num or not api.info then return {} end
  return con_habilidades_desplegadas(api, function()
    local salida = {}
    for i = 1, numero(intentar(api.num)) or 0 do
      local nombre, cabecera, _, rango, maximo = fila_habilidad(api, i)
      if type(nombre) == "string" and not cabecera and rango and not POR_NOMBRE[nombre] and #salida < 60 then
        salida[#salida + 1] = { n = nombre, r = rango, m = maximo }
      end
    end
    return salida
  end)
end

local function x_hechizos()
  local salida = {}
  local total = 0
  local function nombre_rango(i, tipo)
    local r = llamar(GetSpellBookItemName, i, tipo)
    if type(r[1]) ~= "string" and C_SpellBook and C_SpellBook.GetSpellBookItemName then
      r = llamar(C_SpellBook.GetSpellBookItemName, i, 0)
    end
    return r[1], r[2]
  end
  -- Cliente moderno: líneas del libro de hechizos con sus huecos.
  if type(GetNumSpellTabs) ~= "function" and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
      and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
    local banco = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for linea = 1, numero(intentar(C_SpellBook.GetNumSpellBookSkillLines)) or 0 do
      local info = intentar(C_SpellBook.GetSpellBookSkillLineInfo, linea)
      if type(info) == "table" and type(info.name) == "string" then
        local lista = {}
        local desde, cuantos = numero(info.itemIndexOffset) or 0, numero(info.numSpellBookItems) or 0
        for i = desde + 1, desde + cuantos do
          local it = intentar(C_SpellBook.GetSpellBookItemInfo, i, banco)
          if type(it) == "table" and type(it.name) == "string" and not it.isOffSpec and total < 400 then
            local rango = type(it.subName) == "string" and it.subName ~= "" and it.subName or nil
            lista[#lista + 1] = rango and (it.name .. "|" .. rango) or it.name
            total = total + 1
          end
        end
        if #lista > 0 then salida[#salida + 1] = { n = info.name, s = lista } end
      end
    end
    return salida
  end
  local pestanas = numero(intentar(GetNumSpellTabs)) or 0
  for t = 1, pestanas do
    local r = llamar(GetSpellTabInfo, t)
    local nombre, desde, cuantos = r[1], numero(r[3]), numero(r[4])
    if type(nombre) == "string" and desde and cuantos then
      local lista = {}
      for i = desde + 1, desde + cuantos do
        local n, rango = nombre_rango(i, "spell")
        if type(n) == "string" and total < 400 then
          lista[#lista + 1] = (type(rango) == "string" and rango ~= "") and (n .. "|" .. rango) or n
          total = total + 1
        end
      end
      if #lista > 0 then salida[#salida + 1] = { n = nombre, s = lista } end
    end
  end
  return salida
end

local function x_experiencia()
  local a, m = numero(intentar(UnitXP, "player")), numero(intentar(UnitXPMax, "player"))
  if not a or not m or m <= 0 then return nil end
  local d = numero(intentar(GetXPExhaustion))
  return { a = a, m = m, d = d }
end

local function x_bolsas(bolsas)
  local cuenta, orden = {}, {}
  for _, bolsa in ipairs(bolsas) do
    local huecos
    if C_Container and C_Container.GetContainerNumSlots then huecos = numero(intentar(C_Container.GetContainerNumSlots, bolsa))
    else huecos = numero(intentar(GetContainerNumSlots, bolsa)) end
    for hueco = 1, huecos or 0 do
      local id, n
      if C_Container and C_Container.GetContainerItemInfo then
        local info = intentar(C_Container.GetContainerItemInfo, bolsa, hueco)
        if type(info) == "table" then id, n = info.itemID, info.stackCount end
      elseif type(GetContainerItemID) == "function" then
        id = intentar(GetContainerItemID, bolsa, hueco)
        n = llamar(GetContainerItemInfo, bolsa, hueco)[2]
      end
      if type(id) == "number" and id > 0 then
        if not cuenta[id] then cuenta[id] = 0; orden[#orden + 1] = id end
        cuenta[id] = cuenta[id] + (numero(n) or 1)
      end
    end
  end
  local salida = {}
  for _, id in ipairs(orden) do
    if #salida < 200 then
      local o = { i = id, c = cuenta[id] }
      local f = GetItemInfo or (C_Item and C_Item.GetItemInfo)
      local r = llamar(f, id)
      if type(r[1]) == "string" then o.n = r[1] end
      local ic = nombre_icono(r[10] or intentar(GetItemIcon, id))
      if ic then o.ic = ic end
      salida[#salida + 1] = o
    end
  end
  return salida
end

local function x_pvp()
  local pv = {}
  local function t(f, claves)
    local r = llamar(f)
    local o = {}
    for k, nombre in ipairs(claves) do
      if numero(r[k]) then o[nombre] = r[k] end
    end
    return next(o) ~= nil and o or nil
  end
  -- Sistema moderno de honor: nivel y progreso dentro del nivel (p. ej. 0 / 5500).
  local nivel = numero(intentar(UnitHonorLevel, "player"))
  if nivel then
    pv.hl = nivel
    pv.hx = numero(intentar(UnitHonor, "player"))
    pv.hm = numero(intentar(UnitHonorMax, "player"))
  end
  -- Clásico: progreso hacia el siguiente rango (0 a 1) y nombre del rango actual.
  local progreso = numero(intentar(GetPVPRankProgress))
  if progreso and progreso >= 0 and progreso <= 1 then pv.rp = progreso end
  local bruto = numero(intentar(UnitPVPRank, "player"))
  if bruto and bruto >= 5 and bruto <= 18 then
    local nombre = intentar(GetPVPRankInfo, bruto, "player") or intentar(GetPVPRankInfo, bruto)
    if type(nombre) == "string" and nombre ~= "" then pv.rn = nombre:sub(1, 40) end
  end
  local vida = t(GetPVPLifetimeStats, { "hk", "dk" })
  if vida then pv.hk, pv.dk = vida.hk, vida.dk end
  pv.hoy = t(GetPVPSessionStats, { "hk", "ph" })
  pv.ayer = t(GetPVPYesterdayStats, { "hk", "dk", "ph" })
  pv.sem = t(GetPVPThisWeekStats, { "hk", "ph" })
  pv.ant = t(GetPVPLastWeekStats, { "hk", "dk", "ph", "rk" })
  return next(pv) ~= nil and pv or nil
end

local function x_logros()
  if type(GetCategoryList) ~= "function" or type(GetAchievementInfo) ~= "function" then return nil end
  local lista = {}
  local categorias = intentar(GetCategoryList)
  for _, cat in ipairs(type(categorias) == "table" and categorias or {}) do
    for i = 1, numero(intentar(GetCategoryNumAchievements, cat)) or 0 do
      -- id, nombre, puntos, completado, mes, día, año
      local r = llamar(GetAchievementInfo, cat, i)
      if type(r[1]) == "number" and r[4] == true and #lista < 300 then
        local o = { i = r[1], n = r[2], p = numero(r[3]) }
        if numero(r[5]) and numero(r[6]) and numero(r[7]) then
          o.d = string.format("%04d-%02d-%02d", 2000 + r[7], r[5], r[6])
        end
        lista[#lista + 1] = o
      end
    end
  end
  local puntos = numero(intentar(GetTotalAchievementPoints))
  if #lista == 0 and not puntos then return nil end
  return { pt = puntos, l = lista }
end

local function x_monturas()
  local salida = {}
  if C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID then
    local ids = intentar(C_MountJournal.GetMountIDs)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
      local r = llamar(C_MountJournal.GetMountInfoByID, id)
      if type(r[1]) == "string" and r[11] == true and #salida < 200 then salida[#salida + 1] = r[1] end
    end
  end
  return salida
end

local function x_mascotas()
  local salida = {}
  if C_PetJournal and C_PetJournal.GetNumPets and C_PetJournal.GetPetInfoByIndex then
    local total = numero(intentar(C_PetJournal.GetNumPets)) or 0
    for i = 1, total do
      local r = llamar(C_PetJournal.GetPetInfoByIndex, i)
      -- petID, speciesID, owned (3), customName (4), level (5), ..., speciesName (8)
      local nombre = type(r[4]) == "string" and r[4] or r[8]
      if r[3] == true and type(nombre) == "string" and #salida < 200 then salida[#salida + 1] = nombre end
    end
  end
  return salida
end

-- ------------------------------------------------------------------ recetas, rutas de vuelo, misiones, títulos, piedra de hogar

-- Lo que el juego solo da con una ventana abierta (recetas de un oficio, mapa de vuelo) se guarda al abrirla en el archivo
-- de datos del addon, por personaje, y se exporta desde ahí.
local function capturas()
  if type(WFGExportDB) ~= "table" then WFGExportDB = {} end
  if type(WFGExportDB.capturas) ~= "table" then WFGExportDB.capturas = {} end
  local clave = tostring(intentar(UnitName, "player") or "?") .. "-" .. tostring(intentar(GetRealmName) or "?")
  if type(WFGExportDB.capturas[clave]) ~= "table" then WFGExportDB.capturas[clave] = {} end
  return WFGExportDB.capturas[clave]
end

-- Las recetas que muestra ahora la ventana del oficio: (nombre del oficio, [nombres]). Clásico: oficio y «craft» (encantamiento);
-- cliente nuevo: C_TradeSkillUI.
local function leer_recetas_abiertas()
  local lista, oficio, listaIds = {}, nil, {}
  local function anadir(nombre)
    if type(nombre) == "string" and nombre ~= "" and #lista < 300 then lista[#lista + 1] = nombre:sub(1, 60) end
  end
  local n = numero(intentar(GetNumTradeSkills)) or 0
  if n > 0 then
    oficio = intentar(GetTradeSkillLine)
    for i = 1, n do
      local r = llamar(GetTradeSkillInfo, i)
      if r[2] ~= "header" and r[2] ~= "subheader" then anadir(r[1]) end
    end
  end
  if #lista == 0 then
    local c = numero(intentar(GetNumCrafts)) or 0
    if c > 0 then
      oficio = intentar(GetCraftDisplaySkillLine) or intentar(GetCraftName)
      for i = 1, c do
        local r = llamar(GetCraftInfo, i)
        if r[3] ~= "header" then anadir(r[1]) end
      end
    end
  end
  local idoficio = nil
  if #lista == 0 and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
    local base = intentar(C_TradeSkillUI.GetBaseProfessionInfo)
    oficio = type(base) == "table" and (base.professionName or base.name) or nil
    if type(base) == "table" then
      -- El cliente nuevo da el número del oficio (o el del oficio «padre»): sirve igual que el nombre y no depende del idioma.
      for _, k in ipairs({ "parentProfessionID", "professionID" }) do
        if type(base[k]) == "number" and HABILIDADES[base[k]] then idoficio = base[k]; break end
      end
    end
    local ids = intentar(C_TradeSkillUI.GetAllRecipeIDs)
    if type(ids) == "table" then
      for _, id in ipairs(ids) do
        local info = intentar(C_TradeSkillUI.GetRecipeInfo, id)
        if type(info) == "table" and info.learned ~= false then
          anadir(info.name)
          if #listaIds < 600 then listaIds[#listaIds + 1] = id end
        end
      end
    end
  end
  if type(oficio) ~= "string" or #lista == 0 then return nil end
  return oficio, lista, idoficio, listaIds
end

local function guardar_recetas()
  local oficio, lista, idoficio, listaIds = leer_recetas_abiertas()
  if not oficio then return end
  local id = idoficio or POR_NOMBRE[oficio]
  if not id then return end
  local c = capturas()
  c.recetas = c.recetas or {}
  c.recetas[tostring(id)] = lista
  -- Los números de las recetas (solo los da el cliente moderno): permiten saber cuáles faltan sin depender del idioma.
  c.recetas_id = c.recetas_id or {}
  c.recetas_id[tostring(id)] = (listaIds and #listaIds > 0) and listaIds or nil
end

local function guardar_rutas()
  if type(NumTaxiNodes) ~= "function" then return end
  local total = numero(intentar(NumTaxiNodes)) or 0
  local c = capturas()
  local vistas, lista = {}, {}
  for _, nombre in ipairs(c.rutas or {}) do if not vistas[nombre] then vistas[nombre] = true; lista[#lista + 1] = nombre end end
  for i = 1, total do
    local tipo = intentar(TaxiNodeGetType, i)
    local nombre = intentar(TaxiNodeName, i)
    if (tipo == "REACHABLE" or tipo == "CURRENT") and type(nombre) == "string" and nombre ~= "" and not vistas[nombre] and #lista < 150 then
      vistas[nombre] = true
      lista[#lista + 1] = nombre:sub(1, 60)
    end
  end
  c.rutas = lista
end

local function x_piedra()
  local lugar = intentar(GetBindLocation)
  if type(lugar) == "string" and lugar ~= "" then return lugar:sub(1, 60) end
  return nil
end

local function x_titulos()
  local salida = {}
  local total = numero(intentar(GetNumTitles)) or 0
  for i = 1, math.min(total, 200) do
    if intentar(IsTitleKnown, i) then
      local nombre = intentar(GetTitleName, i)
      if type(nombre) == "string" then
        nombre = nombre:gsub("%%s", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if nombre ~= "" and #salida < 100 then salida[#salida + 1] = nombre:sub(1, 40) end
      end
    end
  end
  return salida
end

-- Misiones: las del diario ahora (título, nivel, si está lista para entregar) y cuántas lleva hechas en total.
local function x_misiones()
  local diario, hechas = {}, nil
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, numero(intentar(C_QuestLog.GetNumQuestLogEntries)) or 0 do
      local info = intentar(C_QuestLog.GetInfo, i)
      if type(info) == "table" and not info.isHeader and type(info.title) == "string" and #diario < 30 then
        diario[#diario + 1] = { t = info.title:sub(1, 80), l = numero(info.level), c = info.isComplete and 1 or nil }
      end
    end
  elseif type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
    for i = 1, numero(intentar(GetNumQuestLogEntries)) or 0 do
      local r = llamar(GetQuestLogTitle, i)
      if type(r[1]) == "string" and not r[4] and #diario < 30 then
        diario[#diario + 1] = { t = r[1]:sub(1, 80), l = numero(r[2]), c = (r[6] == 1) and 1 or nil }
      end
    end
  end
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local lista = intentar(C_QuestLog.GetAllCompletedQuestIDs)
    if type(lista) == "table" then
      hechas = #lista
      for _, id in ipairs(lista) do if type(id) == "number" then ids[#ids + 1] = id end end
    end
  elseif type(GetQuestsCompleted) == "function" then
    local t = intentar(GetQuestsCompleted)
    if type(t) == "table" then
      hechas = 0
      for id, hecha in pairs(t) do
        hechas = hechas + 1
        if type(id) == "number" and hecha then ids[#ids + 1] = id end
      end
    end
  end
  -- Los números de las misiones hechas, ordenados y como diferencias ("5,1,1,30…"): ocupan poco en el texto.
  local h
  if #ids > 0 and #ids <= 20000 then
    table.sort(ids)
    local partes, anterior = {}, 0
    for _, id in ipairs(ids) do
      partes[#partes + 1] = string.format("%d", id - anterior)
      anterior = id
    end
    h = table.concat(partes, ",")
  end
  if #diario == 0 and not hechas then return nil end
  return { n = hechas, l = diario, h = h }
end

-- Bolsa de componentes (clientes nuevos) y bolsas del banco. Con la bolsa de componentes, las del banco empiezan en la 6.
local function bolsa_de_componentes()
  local e = Enum and Enum.BagIndex
  return e and type(e.ReagentBag) == "number" and e.ReagentBag or nil
end

local function bolsas_del_banco()
  local lista = { -1 }
  local desde, hasta = 5, 11
  if bolsa_de_componentes() then desde, hasta = 6, 12 end
  for i = desde, hasta do lista[#lista + 1] = i end
  return lista
end

-- El banco solo se puede leer con su ventana abierta: se guarda al abrirla y se exporta desde ahí.
local function guardar_banco()
  local l = x_bolsas(bolsas_del_banco())
  if #l > 0 then capturas().banco = l end
end

-- Tus anuncios en la casa de subastas: solo se pueden leer con ella abierta, así que se guardan al abrirla.
-- Campos: i objeto, n nombre, q cantidad, b compra directa, p puja, t tiempo restante (0 corto ... 3 muy largo), s estado (0 activo, 1 vendido).
local function guardar_subasta()
  local H = C_AuctionHouse
  local lista = {}
  if not (H and H.GetNumOwnedAuctions and H.GetOwnedAuctionInfo) then
    -- Cliente clásico: lista «owner» de la casa de subastas de siempre.
    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then return end
    local total = numero(intentar(GetNumAuctionItems, "owner")) or 0
    for i = 1, math.min(total, 100) do
      local r = llamar(GetAuctionItemInfo, "owner", i)
      -- nombre, textura, cantidad, calidad, usable, nivel, tipo de nivel, puja mínima, incremento, compra directa, puja actual, ..., estado, objeto
      local id = numero(r[17])
      if not id and type(GetAuctionItemLink) == "function" then
        local enlace = intentar(GetAuctionItemLink, "owner", i)
        id = type(enlace) == "string" and tonumber(enlace:match("item:(%d+)")) or nil
      end
      if id then
        local resta = numero(intentar(GetAuctionItemTimeLeft, "owner", i)) -- 1 corto ... 4 muy largo
        lista[#lista + 1] = {
          i = id, n = type(r[1]) == "string" and r[1]:sub(1, 80) or nil, q = numero(r[3]) or 1,
          b = numero(r[10]), p = (numero(r[11]) or 0) > 0 and numero(r[11]) or numero(r[8]), t = resta and (resta - 1) or nil, s = (r[16] == 1) and 1 or 0,
        }
      end
    end
    capturas().subasta = { f = type(time) == "function" and time() or nil, l = lista }
    return
  end
  local total = numero(intentar(H.GetNumOwnedAuctions)) or 0
  for i = 1, math.min(total, 100) do
    local info = intentar(H.GetOwnedAuctionInfo, i)
    if type(info) == "table" then
      local id = type(info.itemKey) == "table" and numero(info.itemKey.itemID) or nil
      local nombre = type(info.itemLink) == "string" and info.itemLink:match("%[(.-)%]") or nil
      if not nombre and id then
        local r = llamar(GetItemInfo or (C_Item and C_Item.GetItemInfo), id)
        if type(r[1]) == "string" then nombre = r[1] end
      end
      if id then
        lista[#lista + 1] = {
          i = id, n = nombre and nombre:sub(1, 80) or nil, q = numero(info.quantity) or 1,
          b = numero(info.buyoutAmount), p = numero(info.bidAmount), t = numero(info.timeLeft), s = numero(info.status),
        }
      end
    end
  end
  capturas().subasta = { f = type(time) == "function" and time() or nil, l = lista }
end

-- Tu correo: solo se puede leer con el buzón abierto, así que se guarda al abrirlo. No se lee el texto de las cartas
-- (el juego las marcaría como leídas). Campos: r remitente, a asunto, m dinero, c contrarreembolso, d días que le quedan,
-- n objetos adjuntos, o nombres de los primeros objetos, l 1 si ya está leída.
local function guardar_correo()
  if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then return end
  local total = numero(intentar(GetInboxNumItems)) or 0
  local lista = {}
  for i = 1, math.min(total, 50) do
    local r = llamar(GetInboxHeaderInfo, i)
    -- paquete, papelería, remitente, asunto, dinero, contrarreembolso, días, objetos (número o sí/no), leída, devuelta...
    local adjuntos = numero(r[8]) or (r[8] and 1 or 0)
    local carta = {
      r = type(r[3]) == "string" and r[3]:sub(1, 40) or nil, a = type(r[4]) == "string" and r[4]:sub(1, 80) or nil,
      m = numero(r[5]), c = numero(r[6]), d = numero(r[7]), n = adjuntos > 0 and adjuntos or nil, l = r[9] and 1 or nil,
    }
    if adjuntos > 0 and type(GetInboxItem) == "function" then
      local nombres = {}
      for k = 1, math.min(adjuntos, 12, 3) do
        local it = llamar(GetInboxItem, i, k)
        if type(it[1]) == "string" then nombres[#nombres + 1] = ((numero(it[4]) or 1) > 1) and (it[1] .. " ×" .. it[4]) or it[1] end
      end
      if #nombres > 0 then carta.o = nombres end
    end
    lista[#lista + 1] = carta
  end
  capturas().correo = { f = type(time) == "function" and time() or nil, l = lista }
end

local PROFESIONES_CON_RECETAS = { [171] = true, [164] = true, [333] = true, [202] = true, [165] = true, [186] = true, [197] = true, [185] = true, [129] = true }

-- Abre una a una las ventanas de tus oficios, guarda sus recetas y las cierra, para no tener que abrirlas a mano.
-- Llama a alTerminar() al acabar, o enseguida si el cliente no deja abrirlas desde el addon.
local function capturar_recetas(alTerminar, verboso)
  local C = C_TradeSkillUI
  local abrir = C and C.OpenTradeSkill
  local function di(t) if verboso then print("|cffffd100WFG recetas:|r " .. t) end end
  local terminado = false
  local function fin() if not terminado then terminado = true; pcall(alTerminar) end end
  if type(abrir) ~= "function" or not (C_Timer and C_Timer.After) then
    di("este cliente no deja abrir los oficios desde el addon (OpenTradeSkill: " .. type(abrir) .. "); abre cada oficio a mano una vez")
    fin()
    return
  end
  local cola = {}
  for _, p in ipairs(profesiones()) do if PROFESIONES_CON_RECETAS[p.i] then cola[#cola + 1] = p end end
  if #cola == 0 then fin(); return end
  local function siguiente(k)
    local p = cola[k]
    if not p then fin(); return end
    local ok, err = pcall(abrir, p.i)
    di(p.n .. ": abrir " .. (ok and "ok" or ("error " .. tostring(err))))
    C_Timer.After(1.5, function()
      local bien = pcall(function()
        pcall(guardar_recetas)
        local oficio, lista = leer_recetas_abiertas()
        di(p.n .. ": ventana «" .. tostring(oficio) .. "» con " .. (lista and #lista or 0) .. " recetas")
        if C.CloseTradeSkill then pcall(C.CloseTradeSkill) end
      end)
      if not bien then fin(); return end
      C_Timer.After(0.3, function() siguiente(k + 1) end)
    end)
  end
  -- Si algo se atasca, a los 20 segundos se sigue igualmente.
  C_Timer.After(20, fin)
  siguiente(1)
end

local function extras()
  local x = {}
  local function poner(clave, valor)
    if valor ~= nil and not (type(valor) == "table" and next(valor) == nil) then x[clave] = valor end
  end
  poner("gu", x_hermandad())
  poner("mo", numero(intentar(GetMoney)))
  poner("mn", x_monedas())
  poner("rp", x_reputaciones())
  poner("sk", x_habilidades())
  poner("sp", x_hechizos())
  poner("xp", x_experiencia())
  poner("bg", x_bolsas({ 0, 1, 2, 3, 4 }))
  local componentes = bolsa_de_componentes()
  if componentes then poner("rb", x_bolsas({ componentes })) end
  -- El banco solo se puede leer con la ventana del banco abierta.
  local banco_vivo = x_bolsas(bolsas_del_banco())
  if #banco_vivo > 0 then capturas().banco = banco_vivo end
  poner("bk", #banco_vivo > 0 and banco_vivo or capturas().banco)
  poner("pv", x_pvp())
  poner("lg", x_logros())
  poner("mt", x_monturas())
  poner("mc", x_mascotas())
  poner("tj", tiempo_jugado)
  poner("hs", x_piedra())
  poner("su", capturas().subasta)
  poner("ml", capturas().correo)
  poner("ti", x_titulos())
  poner("qc", x_misiones())
  local cap = capturas()
  poner("rc", cap.recetas)
  poner("ri", cap.recetas_id)
  poner("tx", cap.rutas)
  local zona = intentar(GetRealZoneText)
  if type(zona) == "string" and zona ~= "" then x.zn = zona end
  local sub = intentar(GetSubZoneText)
  if type(sub) == "string" and sub ~= "" then x.sz = sub end
  return x
end

-- ------------------------------------------------------------------ comando de prueba (/wfgprobar)
-- Dice qué da de verdad el cliente: qué funciones existen y cuántos datos salen de cada cosa.

-- /wfgdatos: qué da el cliente de lo último que exporta el addon (piedra de hogar, títulos, misiones, durabilidad, recetas, rutas).
function ns.ProbarDatos()
  local function di(t) print("|cffffd100WFG datos:|r " .. t) end
  local function f(nombre, v) return nombre .. (type(v) == "function" and " sí" or " no") end
  di("Funciones — " .. table.concat({
    f("GetBindLocation", GetBindLocation), f("GetNumTitles", GetNumTitles), f("IsTitleKnown", IsTitleKnown),
    f("GetInventoryItemDurability", GetInventoryItemDurability), f("GetNumQuestLogEntries", GetNumQuestLogEntries),
    f("GetQuestsCompleted", GetQuestsCompleted), f("C_QuestLog.GetInfo", C_QuestLog and C_QuestLog.GetInfo),
    f("C_QuestLog.GetAllCompletedQuestIDs", C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs),
    f("GetNumTradeSkills", GetNumTradeSkills), f("GetNumCrafts", GetNumCrafts),
    f("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs), f("NumTaxiNodes", NumTaxiNodes),
    f("C_TradeSkillUI.OpenTradeSkill", C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill), f("C_TradeSkillUI.CloseTradeSkill", C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill),
  }, ", "))
  local x = extras()
  local mis = x.qc or {}
  di(string.format("Piedra de hogar: %s · títulos: %d · misiones en el diario: %d · misiones hechas: %s",
    tostring(x.hs or "no la da"), x.ti and #x.ti or 0, mis.l and #mis.l or 0, tostring(mis.n or "no lo da")))
  local con_du = 0
  for _, o in ipairs(equipo()) do if o.du then con_du = con_du + 1 end end
  di("Durabilidad: " .. con_du .. " piezas con durabilidad")
  di(string.format("Subasta: %s · C_AuctionHouse.GetOwnedAuctionInfo %s · anuncios guardados: %s (abre la casa de subastas una vez)",
    C_AuctionHouse and "tabla sí" or "tabla no", (C_AuctionHouse and type(C_AuctionHouse.GetOwnedAuctionInfo) == "function") and "sí" or "no",
    x.su and x.su.l and tostring(#x.su.l) or "ninguno"))
  di(string.format("Bolsa de componentes: índice %s, %d objetos distintos · banco guardado: %d objetos distintos",
    tostring(bolsa_de_componentes()), x.rb and #x.rb or 0, x.bk and #x.bk or 0))
  local pv = x.pv or {}
  di(string.format("PvP: progreso del rango %s · nombre del rango %s · muertes con honor %s", tostring(pv.rp or "no lo da"), tostring(pv.rn or "no lo da"), tostring(pv.hk or "no lo da")))
  local partes = {}
  for id, lista in pairs(x.rc or {}) do partes[#partes + 1] = id .. "=" .. #lista end
  table.sort(partes)
  di("Recetas guardadas (número de oficio=recetas): " .. (#partes > 0 and table.concat(partes, ", ") or "ninguna: abre la ventana de cada oficio una vez"))
  di("Rutas de vuelo guardadas: " .. (x.tx and #x.tx or 0) .. (x.tx and "" or " (habla con un maestro de vuelo una vez)"))
end

-- /wfgganzua: qué da el juego para las habilidades (ganzúa, equitación...). También se ejecuta dentro de /wfgprobar.
function ns.ProbarHabilidades()
  local function di(t) print("|cffffd100WFG habilidades:|r " .. t) end
  local x = { sk = x_habilidades() }
  do
    -- Qué ofrece el juego para las habilidades y qué devuelven sus primeras filas, tal cual.
    local api = api_habilidades()
    local filas = {}
    local total = numero(intentar(api.num))
    for i = 1, math.min(total or 0, 8) do
      local nombre, cabecera, expandida, rango, maximo = fila_habilidad(api, i)
      filas[#filas + 1] = string.format("%d=%s|%s|%s|%s|%s", i, tostring(nombre), tostring(cabecera), tostring(expandida), tostring(rango), tostring(maximo))
    end
    di(string.format("Habilidades (diagnóstico) — GetNumSkillLines=%s, GetSkillLineInfo=%s, ExpandSkillHeader=%s, CollapseSkillHeader=%s, C_SkillInfo=%s, error=%s",
      tostring(total), type(api.info), type(api.expandir), type(api.plegar), type(C_SkillInfo), tostring(ns.errorHabilidades)))
    if #filas > 0 then di("Habilidades (primeras filas nombre|cabecera|expandido|rango|máximo) — " .. table.concat(filas, " ; ")) end
    -- Si el juego da tablas, se enseñan sus campos para ver cómo se llaman.
    local cruda = llamar(api.info, 1)[1]
    if type(cruda) == "table" then
      local campos = {}
      for k, v in pairs(cruda) do if type(v) ~= "table" then campos[#campos + 1] = tostring(k) .. "=" .. tostring(v) end end
      table.sort(campos)
      di("Habilidades (campos de la fila 1) — " .. table.concat(campos, " ", 1, math.min(#campos, 14)))
    end
    local cruda_id = type(api.por_id) == "function" and llamar(api.por_id, 633)[1] or nil
    if type(cruda_id) == "table" then
      local campos = {}
      for k, v in pairs(cruda_id) do if type(v) ~= "table" then campos[#campos + 1] = tostring(k) .. "=" .. tostring(v) end end
      table.sort(campos)
      di("Habilidades (GetSkillLineInfoByID 633) — " .. table.concat(campos, " ", 1, math.min(#campos, 14)))
    end
    local nombres = {}
    for k, v in pairs(_G) do
      if type(k) == "string" and k:lower():find("skill", 1, true) and (type(v) == "function" or type(v) == "table") then nombres[#nombres + 1] = k end
    end
    table.sort(nombres)
    di("Habilidades (funciones del juego con «skill») — " .. (#nombres > 0 and table.concat(nombres, ", ", 1, math.min(#nombres, 40)) or "ninguna"))
  end
  do
    -- El cliente nuevo no tiene la lista antigua: se buscan las tablas C_ que puedan dar las habilidades y se prueban.
    local function claves(t, tope)
      local n = {}
      for k, v in pairs(t) do if type(v) == "function" then n[#n + 1] = tostring(k) end end
      table.sort(n)
      return #n > 0 and table.concat(n, ", ", 1, math.min(#n, tope or 30)) or "(sin funciones)"
    end
    local tablas = {}
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "table" and k:sub(1, 2) == "C_" then
        local bajo = k:lower()
        if bajo:find("skill", 1, true) or bajo:find("prof", 1, true) or bajo:find("trade", 1, true) or bajo:find("spellbook", 1, true) then
          tablas[#tablas + 1] = k
        end
      end
    end
    table.sort(tablas)
    di("Tablas del juego relacionadas — " .. (#tablas > 0 and table.concat(tablas, ", ") or "ninguna"))
    for _, k in ipairs(tablas) do
      if k:lower():find("skill", 1, true) then di(k .. " — " .. claves(_G[k], 40)) end
    end
    for _, k in ipairs({ "SkillsFrameMixin", "SkillsEntryMixin", "SkillsHeaderMixin" }) do
      if type(_G[k]) == "table" then di(k .. " — " .. claves(_G[k], 30)) end
    end
    -- Pruebas con los números de habilidad de la ganzúa (633) y la equitación (762).
    for _, id in ipairs({ 633, 762 }) do
      local fuentes = {
        { "C_TradeSkillUI.GetProfessionInfoBySkillLineID", C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID },
        { "C_SkillLine.GetSkillLineInfo", C_SkillLine and C_SkillLine.GetSkillLineInfo },
        { "C_SkillLine.GetInfo", C_SkillLine and C_SkillLine.GetInfo },
      }
      for _, f in ipairs(fuentes) do
        if type(f[2]) == "function" then
          local ok, r = pcall(f[2], id)
          local txt = tostring(r)
          if ok and type(r) == "table" then
            local partes = {}
            for k, v in pairs(r) do if type(v) ~= "table" then partes[#partes + 1] = tostring(k) .. "=" .. tostring(v) end end
            table.sort(partes)
            txt = table.concat(partes, " ", 1, math.min(#partes, 12))
          end
          di(string.format("Prueba %s(%d) — %s %s", f[1], id, ok and "ok" or "error", txt))
        end
      end
    end
  end
  do
    local lista, ganzua, equitacion = {}, false, false
    for _, h in ipairs(x.sk) do
      lista[#lista + 1] = h.n .. " " .. h.r .. (h.m and ("/" .. h.m) or "")
      local bajo = h.n:lower()
      if bajo == "lockpicking" or bajo == "ganzúa" then ganzua = true end
      if bajo == "riding" or bajo == "equitación" then equitacion = true end
    end
    di("Habilidades leídas (" .. #lista .. ") — ganzúa " .. (ganzua and "sí" or "no") .. ", equitación " .. (equitacion and "sí" or "no")
      .. (#lista > 0 and (": " .. table.concat(lista, ", ", 1, math.min(#lista, 30))) or ""))
  end
end

function ns.Probar()
  local function di(t) print("|cffffd100WFG prueba:|r " .. t) end
  local function existe(nombre, valor) return nombre .. (valor and " |cff00ff00sí|r" or " |cffff4040no|r") end
  di("API — " .. table.concat({
    existe("talentos clásicos", type(GetTalentInfo) == "function"),
    existe("C_Traits", C_Traits ~= nil),
    existe("honor GetHonorCurrency", type(GetHonorCurrency) == "function"),
    existe("C_CurrencyInfo", C_CurrencyInfo ~= nil),
    existe("hermandad", type(GetGuildInfo) == "function"),
    existe("reputación clásica", type(GetNumFactions) == "function"),
    existe("C_Reputation", C_Reputation ~= nil),
    existe("habilidades", type(GetNumSkillLines) == "function"),
    existe("libro de hechizos", type(GetNumSpellTabs) == "function" or (C_SpellBook ~= nil and C_SpellBook.GetNumSpellBookSkillLines ~= nil)),
    existe("C_Container", C_Container ~= nil),
    existe("estadísticas PvP", type(GetPVPLifetimeStats) == "function"),
    existe("logros", type(GetAchievementInfo) == "function"),
    existe("C_MountJournal", C_MountJournal ~= nil),
    existe("C_PetJournal", C_PetJournal ~= nil),
    existe("tiempo jugado", type(RequestTimePlayed) == "function"),
  }, ", "))
  local x = extras()
  local function n(v) return type(v) == "table" and #v or (v and 1 or 0) end
  di(string.format("Datos — hermandad %s, dinero %s, monedas %d, reputaciones %d, habilidades %d, hechizos %d (pestañas %d), experiencia %s",
    x.gu and x.gu.n or "no", x.mo and "sí" or "no", n(x.mn), n(x.rp), n(x.sk), x.sp and (function() local c = 0 for _, p in ipairs(x.sp) do c = c + #p.s end return c end)() or 0, n(x.sp), x.xp and "sí" or "no"))
  ns.ProbarHabilidades()
  di(string.format("Datos — bolsas %d objetos distintos, banco %d (hay que abrirlo), PvP %s, logros %d (puntos %s), monturas %d, mascotas %d, tiempo jugado %s",
    n(x.bg), n(x.bk), x.pv and "sí" or "no", x.lg and #x.lg.l or 0, x.lg and tostring(x.lg.pt) or "?", n(x.mt), n(x.mc), x.tj and "sí" or "pendiente (repite el comando)"))
  local pv = pvp()
  local ex = x.pv or {}
  di("Honor: " .. (pv.honor and tostring(pv.honor) or "no lo da el juego") .. " · rango: " .. (pv.rank and tostring(pv.rank) or "no lo da el juego")
    .. " · nivel de honor: " .. (ex.hl and (tostring(ex.hl) .. " (" .. tostring(ex.hx or "?") .. "/" .. tostring(ex.hm or "?") .. ")") or "no lo da el juego"))
  local nombres_rango, valores_rango = buscar_rango_pvp()
  di("Rango PvP (búsqueda) — funciones con rank/honor: " .. (#nombres_rango > 0 and table.concat(nombres_rango, ", ", 1, math.min(#nombres_rango, 25)) or "ninguna"))
  if #valores_rango > 0 then di("Rango PvP (valores) — " .. table.concat(valores_rango, " · ")) end
  local t, t2 = talentos()
  local puntos, con_pos = 0, 0
  for _, a in ipairs(t) do
    puntos = puntos + (a.p or 0)
    for _, y in ipairs(a.t) do if y.f then con_pos = con_pos + 1 end end
  end
  di(string.format("Talentos — árboles %d, puntos %d, talentos con posición %d, segunda rama %d", #t, puntos, con_pos, #t2))
  -- Diagnóstico de talentos modernos: dónde se pierden los datos.
  if C_Traits and C_ClassTalents then
    local config = intentar(C_ClassTalents.GetActiveConfigID)
    local info = config and intentar(C_Traits.GetConfigInfo, config)
    local ids = type(info) == "table" and info.treeIDs or nil
    di("Talentos (diagnóstico) — configuración " .. tostring(config) .. ", árboles " .. tostring(ids and #ids or "nil"))
    for k, arbolID in ipairs(ids or {}) do
      local nodos = intentar(C_Traits.GetTreeNodes, arbolID)
      local total, validos, con_rango, suma, muestra = 0, 0, 0, 0, ""
      for _, id in ipairs(type(nodos) == "table" and nodos or {}) do
        total = total + 1
        local nodo = intentar(C_Traits.GetNodeInfo, config, id)
        if type(nodo) == "table" then
          validos = validos + 1
          local r = numero(nodo.activeRank) or 0
          local c = numero(nodo.ranksPurchased) or 0
          if r > 0 or c > 0 then
            con_rango = con_rango + 1
            suma = suma + math.max(r, c)
            if muestra == "" then muestra = string.format(" (ej.: activeRank %s, comprados %s)", tostring(nodo.activeRank), tostring(nodo.ranksPurchased)) end
          end
        end
      end
      di(string.format("  árbol %d (id %s): %d nodos, %d leídos, %d con puntos, suma %d%s", k, tostring(arbolID), total, validos, con_rango, suma, muestra))
    end
  else
    di("Talentos (diagnóstico) — no hay C_Traits/C_ClassTalents")
  end
  -- Diagnóstico de la doble especialización y de cómo vienen colocadas las ramas.
  do
    local function nombres_de(tabla, filtro)
      local salida = {}
      if type(tabla) == "table" then
        for k, v in pairs(tabla) do
          if type(k) == "string" and type(v) == "function" and (not filtro or k:lower():find(filtro)) then salida[#salida + 1] = k end
        end
      end
      table.sort(salida)
      return salida
    end
    local function lista(t) return #t > 0 and table.concat(t, ", ", 1, math.min(#t, 30)) or "ninguna" end
    di("Doble especialización — C_ClassTalents: " .. lista(nombres_de(C_ClassTalents)))
    di("Doble especialización — C_SpecializationInfo: " .. lista(nombres_de(C_SpecializationInfo)))
    local globales = {}
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "function" and (k:find("Spec") or k:find("TalentGroup")) and not k:find("^PVP") and not k:find("_") then
        globales[#globales + 1] = k
      end
    end
    table.sort(globales)
    di("Doble especialización — funciones globales: " .. lista(globales))
    local function valor(f, ...)
      local ok, a, b = pcall(f, ...)
      return ok and (tostring(a) .. (b ~= nil and ("," .. tostring(b)) or "")) or "-"
    end
    di(string.format("Doble especialización — valores: GetNumSpecGroups=%s GetActiveSpecGroup=%s GetNumTalentGroups=%s GetNumSpecializations=%s",
      type(GetNumSpecGroups) == "function" and valor(GetNumSpecGroups) or "no",
      type(GetActiveSpecGroup) == "function" and valor(GetActiveSpecGroup) or "no",
      type(GetNumTalentGroups) == "function" and valor(GetNumTalentGroups) or "no",
      type(GetNumSpecializations) == "function" and valor(GetNumSpecializations) or "no"))
    if C_ClassTalents and C_Traits then
      local config = intentar(C_ClassTalents.GetActiveConfigID)
      local info = config and intentar(C_Traits.GetConfigInfo, config)
      for _, arbolID in ipairs(type(info) == "table" and info.treeIDs or {}) do
        local xs, ys = {}, {}
        for _, id in ipairs(intentar(C_Traits.GetTreeNodes, arbolID) or {}) do
          local nodo = intentar(C_Traits.GetNodeInfo, config, id)
          if type(nodo) == "table" and tonumber(nodo.posX) and tonumber(nodo.posY) then xs[#xs + 1] = tonumber(nodo.posX); ys[#ys + 1] = tonumber(nodo.posY) end
        end
        local function resumen(v)
          local d, visto = {}, {}
          for _, x in ipairs(v) do if not visto[x] then visto[x] = true; d[#d + 1] = x end end
          table.sort(d)
          return string.format("%d distintos de %s a %s", #d, tostring(d[1]), tostring(d[#d]))
        end
        di(string.format("Árbol %s — posX %s · posY %s", tostring(arbolID), resumen(xs), resumen(ys)))
      end
    end
  end
  local texto = ns.GenerarTexto()
  di("El texto completo mide " .. #texto .. " letras.")
  ns.PedirTiempo()
end

-- ------------------------------------------------------------------ comando de prueba del aspecto (/wfgaspecto)
-- Dice si el cliente deja leer el aspecto del personaje (piel, cara, peinado...) para dibujarlo en 3D en la app.
function ns.ProbarAspecto()
  local function di(t) print("|cffffd100WFG aspecto:|r " .. t) end
  di("versión del addon " .. VERSION_ADDON .. " — buscando el aspecto de tu personaje")
  local raza, clave = intentar(UnitRace, "player")
  di("Raza: " .. tostring(raza) .. " (" .. tostring(clave) .. ") · sexo: " .. tostring(intentar(UnitSex, "player")))
  -- Aspecto del personaje (piel, cara, pelo...) para dibujarlo en 3D en la app.
  -- Se buscan funciones con nombres de personalización; la transfiguración (C_TransmogCollection) no sirve y se deja fuera.
  do
    local hallados = {}
    local function mirar(prefijo, tabla)
      if type(tabla) ~= "table" then return end
      for k, v in pairs(tabla) do
        if type(k) == "string" and type(v) == "function" then
          local m = k:lower()
          if m:find("customiz") or m:find("barber") or m:find("charactermodel") or m:find("playercharacterdata")
              or m:find("hairstyle") or m:find("skincolor") or m:find("facialhair") or m:find("charactercreate") then
            hallados[#hallados + 1] = prefijo .. k
          end
        end
      end
    end
    mirar("", _G)
    for _, t in ipairs({ "C_PlayerInfo", "C_BarberShop", "C_ChrCustomization", "C_CharacterCreation", "C_CharacterCustomization" }) do
      if type(_G[t]) == "table" then
        local antes = #hallados
        for k, v in pairs(_G[t]) do
          if type(k) == "string" and type(v) == "function" and (t ~= "C_PlayerInfo" or k:lower():find("char") or k:lower():find("custom")) then
            hallados[#hallados + 1] = t .. "." .. k
          end
        end
        if #hallados == antes then hallados[#hallados + 1] = t .. " (vacía)" end
      end
    end
    -- Solo las de lectura (Get/Is/Has): el resto cambia cosas del personaje y no interesa.
    local lecturas = {}
    for _, nombre in ipairs(hallados) do
      if nombre:find("%.Get") or nombre:find("^Get") or nombre:find("%.Is") or nombre:find("%.Has") then lecturas[#lecturas + 1] = nombre end
    end
    table.sort(lecturas)
    di("Aspecto del personaje — " .. #hallados .. " funciones, " .. #lecturas .. " de lectura")
    for i = 1, math.min(#lecturas, 40), 8 do
      di("  " .. table.concat(lecturas, ", ", i, math.min(i + 7, #lecturas, 40)))
    end
  end
  -- ¿Qué devuelve C_PlayerInfo.GetPlayerCharacterData? Se vuelca de forma compacta (tablas hasta 3 niveles).
  do
    local function volcar(v, nivel)
      local t = type(v)
      if t == "string" then return '"' .. v:sub(1, 40) .. '"' end
      if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
      if t ~= "table" then return "<" .. t .. ">" end
      if nivel >= 3 then return "{...}" end
      local partes, n = {}, 0
      for k, x in pairs(v) do
        n = n + 1
        if n > 25 then partes[#partes + 1] = "…"; break end
        partes[#partes + 1] = tostring(k) .. "=" .. volcar(x, nivel + 1)
      end
      return "{" .. table.concat(partes, ", ") .. "}"
    end
    local candidatas = {
      { "GetPlayerCharacterData", C_PlayerInfo and C_PlayerInfo.GetPlayerCharacterData },
      { "C_BarberShop.GetCurrentCharacterData", C_BarberShop and C_BarberShop.GetCurrentCharacterData },
      { "C_BarberShop.GetAvailableCustomizations", C_BarberShop and C_BarberShop.GetAvailableCustomizations },
    }
    for _, c in ipairs(candidatas) do
      local nombre, f = c[1], c[2]
      if type(f) ~= "function" then
        di(nombre .. " — no existe")
      else
        for _, args in ipairs({ {}, { "player" } }) do
          local ok, r = pcall(f, desempaquetar(args))
          local texto = ok and volcar(r, 0) or ("error: " .. tostring(r))
          di(nombre .. "(" .. (#args > 0 and '"player"' or "") .. ") — " .. #texto .. " letras")
          for i = 1, math.min(#texto, 900), 180 do di("  " .. texto:sub(i, i + 179)) end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ el segundo nombre

-- En WoW Forever un personaje puede tener dos nombres que se ven a la vez (el segundo hace de «apellido»).
-- No se sabe de antemano qué función del juego lo devuelve, así que se miran varias y se toma el primer texto que sea
-- «nombre + espacio + algo». /wfgnombres enseña todo lo que dan para poder afinarlo.
local function nombres_del_personaje()
  local nombre, segundo = intentar(UnitName, "player")
  local reino = intentar(GetRealmName)
  local candidatos = {}
  local function anadir(origen, texto)
    if type(texto) == "string" and texto ~= "" then candidatos[#candidatos + 1] = { origen = origen, texto = texto } end
  end
  anadir("UnitName (segundo valor)", segundo)
  anadir("GetUnitName", intentar(GetUnitName, "player"))
  local _, completo = intentar(UnitFullName, "player")
  anadir("UnitFullName (segundo valor)", completo)
  pcall(function()
    if PlayerName and PlayerName.GetText then anadir("marco del jugador", PlayerName:GetText()) end
    if PlayerFrame and PlayerFrame.name and PlayerFrame.name.GetText then anadir("PlayerFrame.name", PlayerFrame.name:GetText()) end
  end)
  anadir("UnitPVPName (lleva título)", intentar(UnitPVPName, "player"))
  return nombre, reino, candidatos
end

local function apellido_del_personaje()
  local nombre, reino, candidatos = nombres_del_personaje()
  if type(nombre) ~= "string" or nombre == "" then return nil end
  for _, c in ipairs(candidatos) do
    if not c.origen:find("UnitPVPName", 1, true) then
      local t = c.texto
      local resto
      if t:sub(1, #nombre + 1) == nombre .. " " then
        resto = t:sub(#nombre + 2)
      elseif c.origen == "UnitName (segundo valor)" and t ~= reino and not t:find("-", 1, true) then
        resto = t -- el segundo valor de UnitName suele ser el reino: si no lo es, es el segundo nombre
      end
      if resto then
        resto = resto:gsub("^%s+", ""):gsub("%s+$", "")
        if #resto >= 2 and #resto <= 24 then return resto end
      end
    end
  end
  return nil
end

-- /wfgversion: qué versión del addon está cargada, y la del .toc por si no coinciden (archivos mezclados al copiar).
function ns.MostrarVersion()
  local leer = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local toc = type(leer) == "function" and intentar(leer, "WoWForeverGuideExport", "Version") or nil
  print("|cffffd100WoW Forever Guide:|r versión del código " .. VERSION_ADDON .. " · versión del .toc " .. tostring(toc or "?")
    .. ((toc and toc ~= VERSION_ADDON) and " — NO COINCIDEN: borra la carpeta del addon y copia la nueva" or ""))
end

function ns.MostrarNombres()
  local nombre, reino, candidatos = nombres_del_personaje()
  print("|cffffd100WoW Forever Guide:|r nombre = " .. tostring(nombre) .. " · reino = " .. tostring(reino))
  for _, c in ipairs(candidatos) do print("  " .. c.origen .. " → «" .. c.texto .. "»") end
  print("  segundo nombre que se exportará: " .. tostring(apellido_del_personaje() or "ninguno"))
end

-- ------------------------------------------------------------------ el texto

function ns.GenerarTexto()
  local nombre = intentar(UnitName, "player")
  local datos = { v = VERSION_FORMATO, n = nombre or "?" }
  local reino = intentar(GetRealmName)
  if reino and reino ~= "" then datos.r = reino end
  local apellido = apellido_del_personaje()
  if apellido then datos.n2 = apellido end
  local faccion = intentar(UnitFactionGroup, "player")
  if faccion == "Alliance" then datos.f = "A" elseif faccion == "Horde" then datos.f = "H" end
  local _, clase = intentar(UnitClass, "player") -- (nombre en tu idioma, clave en inglés: "MAGE")
  if type(clase) == "string" then datos.c = clase end
  local nivel = intentar(UnitLevel, "player")
  if nivel then datos.l = nivel end
  local _, raza = intentar(UnitRace, "player") -- (nombre en tu idioma, clave en inglés: "NightElf")
  if type(raza) == "string" and raza ~= "" then datos.ra = raza end
  local sexo = intentar(UnitSex, "player") -- 2 = hombre, 3 = mujer
  if sexo == 2 then datos.sx = "M" elseif sexo == 3 then datos.sx = "F" end
  datos.p = profesiones()
  local p = pvp()
  if next(p) ~= nil then datos.pvp = p end
  local g = equipo()
  if #g > 0 then datos.g = g end
  local st = estadisticas()
  if next(st) ~= nil then datos.st = st end
  local t, t2, activa = talentos()
  if #t > 0 then datos.t = t end
  if #t2 > 0 then datos.t2 = t2 end
  if activa and (#t > 0 or #t2 > 0) then datos.ta = activa end
  local x = extras()
  if next(x) ~= nil then datos.x = x end
  return PREFIJO .. a_json(datos), datos
end

-- ------------------------------------------------------------------ ventana

local ventana

local function crear_ventana()
  local f
  pcall(function() f = CreateFrame("Frame", "WFGExportFrame", UIParent, "BasicFrameTemplateWithInset") end)
  if not f then
    f = CreateFrame("Frame", "WFGExportFrame", UIParent, "BackdropTemplate")
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 },
      })
    end
  end
  f:SetSize(520, 130)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local titulo = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titulo:SetPoint("TOP", f, "TOP", 0, -8)
  titulo:SetText("WoW Forever Guide: exportar personaje")

  local ayuda = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ayuda:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
  ayuda:SetPoint("RIGHT", f, "RIGHT", -18, 0)
  ayuda:SetJustifyH("LEFT")
  ayuda:SetText("Pulsa Ctrl+C para copiar el texto y pégalo en la app (Importar personaje).")

  local caja = CreateFrame("EditBox", nil, f)
  caja:SetFontObject("ChatFontNormal")
  caja:SetSize(480, 24)
  caja:SetPoint("TOP", f, "TOP", 0, -72)
  caja:SetAutoFocus(true)
  caja:SetMaxLetters(0)
  caja:SetScript("OnEscapePressed", function() f:Hide() end)
  caja:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  -- El texto no se puede editar: si se toca, se restaura y se vuelve a seleccionar.
  caja:SetScript("OnTextChanged", function(self, usuario)
    if usuario and f.texto then
      self:SetText(f.texto)
      self:HighlightText()
    end
  end)
  f.caja = caja

  local ok, cerrar = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
  if ok and cerrar then
    cerrar:SetSize(100, 22)
    cerrar:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    cerrar:SetText("Cerrar")
    cerrar:SetScript("OnClick", function() f:Hide() end)
  end
  f:Hide()
  return f
end

function ns.Mostrar()
  local texto, datos = ns.GenerarTexto()
  -- Una línea de resumen en el chat, para ver al momento si se han leído las habilidades (ganzúa, equitación...).
  local sk = datos.x and datos.x.sk or {}
  local ganzua, equitacion = false, false
  for _, h in ipairs(sk) do
    local bajo = tostring(h.n):lower()
    if bajo == "lockpicking" or bajo == "ganzúa" then ganzua = true end
    if bajo == "riding" or bajo == "equitación" then equitacion = true end
  end
  print("|cffffd100WoW Forever Guide " .. VERSION_ADDON .. ":|r habilidades leídas " .. #sk .. " (ganzúa " .. (ganzua and "sí" or "no") .. ", equitación " .. (equitacion and "sí" or "no") .. ")"
    .. (#sk == 0 and " — escribe /wfgganzua y mándame lo que salga" or ""))
  do
    local x = datos.x or {}
    local recetas = 0
    for _, lista in pairs(x.rc or {}) do recetas = recetas + #lista end
    print(string.format("|cffffd100WoW Forever Guide:|r recetas %d · rutas de vuelo %d · títulos %d · misiones en el diario %d · piedra de hogar %s · anuncios en la subasta %s · cartas en el correo %s · banco %d objetos",
      recetas, x.tx and #x.tx or 0, x.ti and #x.ti or 0, x.qc and x.qc.l and #x.qc.l or 0, tostring(x.hs or "?"),
      x.su and x.su.l and tostring(#x.su.l) or "sin guardar", x.ml and x.ml.l and tostring(#x.ml.l) or "sin guardar", x.bk and #x.bk or 0))
  end
  ventana = ventana or crear_ventana()
  ventana.texto = texto
  ventana.caja:SetText(texto)
  ventana:Show()
  ventana.caja:SetFocus()
  ventana.caja:HighlightText()
  -- Se guarda también en el archivo de datos del addon (se escribe al salir o con /reload).
  ns.GuardarEnArchivo(texto, datos)
end

function ns.GuardarEnArchivo(texto, datos)
  WFGExportDB = WFGExportDB or {}
  local clave = (datos.n or "?") .. "-" .. (datos.r or "?")
  WFGExportDB[clave] = { texto = texto, fecha = date and date("%Y-%m-%d %H:%M:%S") or "" }
end

-- Botón del minimapa: un clic lee el personaje, lo deja en el archivo del addon y recarga la interfaz
-- (el juego solo escribe ese archivo al recargar o salir).
local exportando = false

local function recargar_interfaz()
  -- Se prueba ReloadUI y, si el cliente lo bloquea, la consola. Si a los 2 segundos seguimos aquí, se avisa.
  local ok1, err1 = pcall(ReloadUI)
  if not ok1 then print("|cffff5555WoW Forever Guide:|r ReloadUI falló: " .. tostring(err1)) end
  if type(ConsoleExec) == "function" then pcall(ConsoleExec, "reloadui") end
  if C_Timer and C_Timer.After then
    C_Timer.After(2, function()
      print("|cffffd100WoW Forever Guide:|r el juego no deja recargar desde un addon. Tu personaje ya está guardado: escribe /reload.")
    end)
  end
end

function ns.ExportarYRecargar()
  if exportando then return end
  if InCombatLockdown and InCombatLockdown() then
    print("|cffffd100WoW Forever Guide:|r no se puede recargar en combate; inténtalo al terminar.")
    return
  end
  exportando = true
  -- Si algo se atasca, se libera el botón a los 40 segundos.
  if C_Timer and C_Timer.After then C_Timer.After(40, function() exportando = false end) end
  ns.PedirTiempo()
  pedir_hermandad()
  print("|cffffd100WoW Forever Guide:|r leyendo tu personaje (unos segundos); después se recargará la interfaz...")
  capturar_recetas(function()
    local ok, texto, datos = pcall(ns.GenerarTexto)
    if not (ok and texto) then
      exportando = false
      print("|cffff5555WoW Forever Guide:|r no se ha podido leer el personaje: " .. tostring(texto))
      return
    end
    ns.GuardarEnArchivo(texto, datos)
    print("|cffffd100WoW Forever Guide:|r personaje guardado. Recargando...")
    if C_Timer and C_Timer.After then
      -- Un instante para que se vea el mensaje y se terminen las lecturas pendientes.
      C_Timer.After(0.5, function() exportando = false; recargar_interfaz() end)
    else
      exportando = false
      recargar_interfaz()
    end
  end, false)
end

local function ajustes_minimapa()
  if type(WFGExportDB) ~= "table" then WFGExportDB = {} end
  if type(WFGExportDB.minimapa) ~= "table" then WFGExportDB.minimapa = {} end
  return WFGExportDB.minimapa
end

local function colocar_boton(b)
  local aj = ajustes_minimapa()
  local angulo = math.rad(tonumber(aj.angulo) or 215)
  local radio = (Minimap:GetWidth() / 2) + 5
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angulo) * radio, math.sin(angulo) * radio)
end

local function crear_boton_minimapa()
  if not Minimap or not Minimap.GetWidth or _G.WFGMinimapButton then return end
  local b = CreateFrame("Button", "WFGMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  pcall(b.SetHighlightTexture, b, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icono = b:CreateTexture(nil, "BACKGROUND")
  icono:SetSize(20, 20)
  icono:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -5)
  icono:SetTexture("Interface\\AddOns\\WoWForeverGuideExport\\icono")
  local borde = b:CreateTexture(nil, "OVERLAY")
  borde:SetSize(53, 53)
  borde:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  borde:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  b:SetScript("OnClick", function() ns.ExportarYRecargar() end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("WoW Forever Guide")
    GameTooltip:AddLine("Clic: exportar el personaje y recargar", 1, 1, 1)
    GameTooltip:AddLine("Arrastrar: mover el botón", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local e = Minimap:GetEffectiveScale()
      local atan = math.atan2 or math.atan
      ajustes_minimapa().angulo = math.deg(atan(cy / e - my, cx / e - mx)) % 360
      colocar_boton(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  colocar_boton(b)
  if ajustes_minimapa().oculto then b:Hide() else b:Show() end
end

function ns.AlternarBoton()
  local aj = ajustes_minimapa()
  aj.oculto = not aj.oculto
  if _G.WFGMinimapButton then
    if aj.oculto then _G.WFGMinimapButton:Hide() else _G.WFGMinimapButton:Show() end
  end
  print("|cffffd100WoW Forever Guide:|r botón del minimapa " .. (aj.oculto and "oculto (/wfgboton para volver a verlo)" or "visible"))
end

-- ------------------------------------------------------------------ arranque

if type(CreateFrame) == "function" then
  SLASH_WFGEXPORT1 = "/wfg"
  SlashCmdList = SlashCmdList or {}
  SlashCmdList["WFGEXPORT"] = function()
    ns.PedirTiempo()
    pedir_hermandad()
    print("|cffffd100WoW Forever Guide:|r leyendo las recetas de tus oficios (unos segundos)...")
    capturar_recetas(function() ns.Mostrar() end, false)
  end
  SLASH_WFGRECETAS1 = "/wfgrecetas"
  SlashCmdList["WFGRECETAS"] = function() capturar_recetas(function() ns.ProbarDatos() end, true) end
  SLASH_WFGVERSION1 = "/wfgversion"
  SlashCmdList["WFGVERSION"] = function() ns.MostrarVersion() end
  SLASH_WFGDATOS1 = "/wfgdatos"
  SlashCmdList["WFGDATOS"] = function() ns.ProbarDatos() end
  SLASH_WFGGANZUA1 = "/wfgganzua"
  SlashCmdList["WFGGANZUA"] = function() ns.ProbarHabilidades() end
  SLASH_WFGPROBAR1 = "/wfgprobar"
  SlashCmdList["WFGPROBAR"] = function() ns.Probar() end
  SLASH_WFGNOMBRES1 = "/wfgnombres"
  SlashCmdList["WFGNOMBRES"] = function() ns.MostrarNombres() end
  SLASH_WFGASPECTO1 = "/wfgaspecto"
  SlashCmdList["WFGASPECTO"] = function() ns.ProbarAspecto() end
  SLASH_WFGBOTON1 = "/wfgboton"
  SlashCmdList["WFGBOTON"] = function() ns.AlternarBoton() end
  SLASH_WFGRECARGAR1 = "/wfgrecargar"
  SlashCmdList["WFGRECARGAR"] = function() ns.ExportarYRecargar() end

  local marco = CreateFrame("Frame")
  marco:RegisterEvent("PLAYER_LOGIN")
  pcall(function() marco:RegisterEvent("GUILDBANKFRAME_OPENED") end)
  pcall(function() marco:RegisterEvent("GUILDBANK_UPDATE_MONEY") end)
  for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
      "CRAFT_SHOW", "CRAFT_UPDATE", "TAXIMAP_OPENED", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW", "OWNED_AUCTIONS_UPDATED", "AUCTION_OWNED_LIST_UPDATE", "MAIL_SHOW", "MAIL_INBOX_UPDATE" }) do
    pcall(function() marco:RegisterEvent(e) end)
  end
  marco:SetScript("OnEvent", function(_, evento)
    if evento == "GUILDBANKFRAME_OPENED" or evento == "GUILDBANK_UPDATE_MONEY" then
      recordar_banco_hermandad()
      return
    end
    if evento == "TRADE_SKILL_SHOW" or evento == "TRADE_SKILL_UPDATE" or evento == "TRADE_SKILL_LIST_UPDATE"
        or evento == "TRADE_SKILL_DATA_SOURCE_CHANGED" or evento == "CRAFT_SHOW" or evento == "CRAFT_UPDATE" then
      pcall(guardar_recetas)
      return
    end
    if evento == "MAIL_SHOW" or evento == "MAIL_INBOX_UPDATE" then
      pcall(guardar_correo)
      return
    end
    if evento == "AUCTION_HOUSE_SHOW" then
      if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {})
      elseif type(GetOwnerAuctionItems) == "function" then pcall(GetOwnerAuctionItems) end
      return
    end
    if evento == "OWNED_AUCTIONS_UPDATED" or evento == "AUCTION_OWNED_LIST_UPDATE" then
      pcall(guardar_subasta)
      return
    end
    if evento == "BANKFRAME_OPENED" then
      pcall(guardar_banco)
      if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(guardar_banco) end) end
      return
    end
    if evento == "TAXIMAP_OPENED" then
      pcall(guardar_rutas)
      return
    end
    pcall(crear_boton_minimapa)
    pedir_hermandad()
    print("|cffffd100WoW Forever Guide:|r escribe /wfg o pulsa el botón del minimapa para exportar tu personaje (/wfgboton lo oculta; /wfgprobar para ver qué da tu cliente, /wfgaspecto para probar el aspecto, /wfgnombres para ver tus dos nombres).")
    ns.PedirTiempo()
  end)
end
