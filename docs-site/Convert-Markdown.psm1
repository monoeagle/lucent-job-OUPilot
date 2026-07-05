# docs-site/Convert-Markdown.psm1 — Minimaler, abhaengigkeitsfreier Markdown->HTML
# Konverter fuer die OUPilot-Doku-Site. Deckt genau die im Repo genutzten
# Konstrukte ab: Ueberschriften, Absaetze, Listen (inkl. Task-Listen + Nesting,
# mit Zeilenumbruch-Fortsetzungen), Codebloecke (```), Inline-Code, fett/kursiv,
# Links, Tabellen (GFM), Blockquotes (>) und horizontale Linien (---).
# Bewusst kein externes Tooling (No-CDN, offline, PowerShell-nativ).

function _Html-Escape { param([string]$s)
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function _Slug { param([string]$s)
    $t = $s.ToLowerInvariant()
    $t = $t -replace '`', '' -replace '\*', '' -replace '_', ''
    $t = $t -replace '[^a-z0-9äöüß \-]', ''
    $t = $t.Trim() -replace '\s+', '-'
    return $t
}

function _Inline { param([string]$text)
    if ($null -eq $text) { return '' }
    $nul = [char]0
    $codes = New-Object System.Collections.Generic.List[string]

    # 1) Inline-Code schuetzen (roh entnehmen, Inhalt escapen, Platzhalter setzen).
    $text = [regex]::Replace($text, '`([^`]+)`', {
        param($m)
        $idx = $codes.Count
        $codes.Add((_Html-Escape $m.Groups[1].Value))
        return "$nul$idx$nul"
    })

    # 2) HTML escapen (der restliche Text).
    $text = _Html-Escape $text

    # 3) Links [Text](url)  (url roh; & wurde bereits zu &amp; -> gueltig).
    $text = [regex]::Replace($text, '\[([^\]]+)\]\(([^)]+)\)', {
        param($m)
        $lbl = $m.Groups[1].Value
        $url = $m.Groups[2].Value
        $ext = if ($url -match '^https?://') { ' target="_blank" rel="noopener"' } else { '' }
        return "<a href=""$url""$ext>$lbl</a>"
    })

    # 4) Fett, dann kursiv.
    $text = [regex]::Replace($text, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $text = [regex]::Replace($text, '(?<!\*)\*(?!\s)([^*]+?)(?<!\s)\*(?!\*)', '<em>$1</em>')

    # 5) Code-Platzhalter zuruecksetzen.
    for ($i = 0; $i -lt $codes.Count; $i++) {
        $text = $text.Replace("$nul$i$nul", "<code>$($codes[$i])</code>")
    }
    return $text
}

function _Render-List { param([object[]]$Nodes)
    if (-not $Nodes -or $Nodes.Count -eq 0) { return '' }
    $ordered = [bool]$Nodes[0].Ordered
    $tag = if ($ordered) { 'ol' } else { 'ul' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<$tag>")
    foreach ($n in $Nodes) {
        $cls = if ($n.Task) { ' class="task"' } else { '' }
        [void]$sb.Append("<li$cls>")
        if ($n.Task) {
            $on = if ($n.Checked) { ' on' } else { '' }
            [void]$sb.Append("<span class=""chk$on""></span>")
        }
        [void]$sb.Append((_Inline $n.Text))
        if ($n.Children -and $n.Children.Count -gt 0) {
            [void]$sb.Append((_Render-List $n.Children))
        }
        [void]$sb.Append('</li>')
    }
    [void]$sb.Append("</$tag>")
    return $sb.ToString()
}

function _Parse-ListBlock { param([string[]]$Lines)
    # Baut aus zusammenhaengenden Listenzeilen (inkl. Fortsetzungen) einen Baum.
    $itemRe = '^(?<indent>\s*)(?<marker>[-*+]|\d+\.)\s+(?<text>.*)$'
    $root  = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.List[object]   # @{ Indent; Node }

    foreach ($ln in $Lines) {
        $m = [regex]::Match($ln, $itemRe)
        if ($m.Success) {
            $indent = $m.Groups['indent'].Value.Length
            $ordered = $m.Groups['marker'].Value -match '^\d+\.'
            $text = $m.Groups['text'].Value
            $task = $false; $checked = $false
            $tm = [regex]::Match($text, '^\[( |x|X)\]\s+(.*)$')
            if ($tm.Success) { $task = $true; $checked = ($tm.Groups[1].Value -ne ' '); $text = $tm.Groups[2].Value }

            $node = [ordered]@{
                Indent = $indent; Ordered = $ordered; Task = $task; Checked = $checked
                Text = $text; Children = (New-Object System.Collections.Generic.List[object])
            }
            while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $indent) {
                $stack.RemoveAt($stack.Count - 1)
            }
            if ($stack.Count -eq 0) { [void]$root.Add($node) }
            else { [void]$stack[$stack.Count - 1].Node.Children.Add($node) }
            [void]$stack.Add([ordered]@{ Indent = $indent; Node = $node })
        }
        elseif ($ln.Trim() -ne '' -and $stack.Count -gt 0) {
            # Fortsetzungszeile -> an aktuelles Item anhaengen.
            $cur = $stack[$stack.Count - 1].Node
            $cur.Text = $cur.Text + ' ' + $ln.Trim()
        }
    }
    return (_Render-List $root)
}

function ConvertFrom-OupMarkdown {
    <#
        .SYNOPSIS  Wandelt Markdown in HTML (Body) + sammelt H1/H2 fuer die Navigation.
        .OUTPUTS   @{ Html = <string>; Headings = @( @{ Level; Text; Id } ) }
    #>
    param([Parameter(Mandatory)][string]$Markdown)

    $lines = $Markdown -replace "`r`n", "`n" -split "`n"
    $out = New-Object System.Text.StringBuilder
    $headings = New-Object System.Collections.Generic.List[object]
    $n = $lines.Count
    $i = 0

    while ($i -lt $n) {
        $line = $lines[$i]

        # Leerzeile
        if ($line.Trim() -eq '') { $i++; continue }

        # Codeblock ``` (auch eingerueckt, z. B. innerhalb einer Liste)
        if ($line -match '^(\s*)```+(.*)$') {
            $ind  = $Matches[1].Length
            $lang = $Matches[2].Trim()
            $code = New-Object System.Collections.Generic.List[string]
            $i++
            while ($i -lt $n -and ($lines[$i] -notmatch '^\s*```+\s*$')) { $code.Add($lines[$i]); $i++ }
            $i++  # schliessendes ``` ueberspringen
            $cls = if ($lang) { " class=""lang-$lang""" } else { '' }
            $esc = ($code | ForEach-Object {
                $t = $_
                if ($ind -gt 0 -and $t.Length -ge $ind -and ($t.Substring(0, $ind)).Trim() -eq '') { $t = $t.Substring($ind) }
                _Html-Escape $t
            }) -join "`n"
            [void]$out.Append("<pre><code$cls>$esc</code></pre>")
            continue
        }

        # Ueberschrift
        if ($line -match '^(#{1,6})\s+(.*)$') {
            $lvl = $Matches[1].Length
            $raw = $Matches[2].Trim()
            $id = _Slug $raw
            [void]$out.Append("<h$lvl id=""$id"">$(_Inline $raw)</h$lvl>")
            if ($lvl -le 2) { [void]$headings.Add([ordered]@{ Level = $lvl; Text = ($raw -replace '[`*]', ''); Id = $id }) }
            $i++; continue
        }

        # Horizontale Linie
        if ($line -match '^\s*---+\s*$') { [void]$out.Append('<hr>'); $i++; continue }

        # Blockquote
        if ($line -match '^\s*>\s?(.*)$') {
            $q = New-Object System.Collections.Generic.List[string]
            while ($i -lt $n -and $lines[$i] -match '^\s*>\s?(.*)$') { $q.Add($Matches[1]); $i++ }
            [void]$out.Append("<blockquote><p>$(_Inline ($q -join ' '))</p></blockquote>")
            continue
        }

        # Tabelle (GFM): aktuelle Zeile mit '|' + naechste Zeile ist Trenner
        if ($line -match '\|' -and ($i + 1) -lt $n -and $lines[$i + 1] -match '^\s*\|?[\s:|-]+\|?\s*$' -and $lines[$i + 1] -match '-') {
            $split = { param($l) ($l.Trim() -replace '^\|', '' -replace '\|$', '') -split '\|' | ForEach-Object { $_.Trim() } }
            $head = & $split $line
            $i += 2
            [void]$out.Append('<div class="table-wrap"><table><thead><tr>')
            foreach ($h in $head) { [void]$out.Append("<th>$(_Inline $h)</th>") }
            [void]$out.Append('</tr></thead><tbody>')
            while ($i -lt $n -and $lines[$i].Trim() -ne '' -and $lines[$i] -match '\|') {
                $cells = & $split $lines[$i]
                [void]$out.Append('<tr>')
                foreach ($c in $cells) { [void]$out.Append("<td>$(_Inline $c)</td>") }
                [void]$out.Append('</tr>')
                $i++
            }
            [void]$out.Append('</tbody></table></div>')
            continue
        }

        # Liste (inkl. Task-Listen, Nesting, Fortsetzungen)
        if ($line -match '^\s*([-*+]|\d+\.)\s+') {
            $block = New-Object System.Collections.Generic.List[string]
            while ($i -lt $n) {
                $l = $lines[$i]
                if ($l.Trim() -eq '') { break }
                # Sub-Block (Codeblock/Blockquote) beendet die Liste -> wird vom
                # Block-Parser korrekt gerendert; danach beginnt ggf. eine neue Liste.
                if ($l -match '^\s*```' -or $l -match '^\s*>\s') { break }
                if ($l -match '^\s*([-*+]|\d+\.)\s+' -or $l -match '^\s{2,}\S') { $block.Add($l); $i++; continue }
                break
            }
            [void]$out.Append((_Parse-ListBlock -Lines $block.ToArray()))
            continue
        }

        # Absatz: bis Leerzeile oder Blockstart sammeln
        $para = New-Object System.Collections.Generic.List[string]
        while ($i -lt $n) {
            $l = $lines[$i]
            if ($l.Trim() -eq '') { break }
            if ($l -match '^\s*```' -or $l -match '^#{1,6}\s' -or $l -match '^\s*>\s' -or `
                $l -match '^\s*---+\s*$' -or $l -match '^\s*([-*+]|\d+\.)\s+') { break }
            $para.Add($l.Trim()); $i++
        }
        if ($para.Count -gt 0) {
            [void]$out.Append("<p>$(_Inline ($para -join ' '))</p>")
        }
    }

    return @{ Html = $out.ToString(); Headings = $headings.ToArray() }
}

Export-ModuleMember -Function ConvertFrom-OupMarkdown
