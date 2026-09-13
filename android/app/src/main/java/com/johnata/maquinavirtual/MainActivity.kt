package com.johnata.maquinavirtual

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.inputmethod.InputMethodManager
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

class MainActivity : Activity() {

    private lateinit var root: FrameLayout
    private var webView: WebView? = null
    private var topBar: View? = null
    private var bottomDock: View? = null
    private var statusLabel: TextView? = null

    private var currentPassword: String = ""
    private var currentBaseUrl: String = ""
    private var currentResolution: String = "1600x720"
    private var allowedHost: String = ""
    private var remoteFullscreen = false

    private val prefs by lazy { getSharedPreferences("maquina_virtual", MODE_PRIVATE) }

    private val bgColor = Color.rgb(7, 10, 18)
    private val panelColor = Color.rgb(15, 20, 34)
    private val panel2Color = Color.rgb(22, 29, 48)
    private val borderColor = Color.rgb(43, 53, 80)
    private val primaryTextColor = Color.rgb(246, 248, 255)
    private val mutedColor = Color.rgb(158, 168, 198)
    private val accentColor = Color.rgb(126, 92, 255)
    private val accent2Color = Color.rgb(101, 145, 255)
    private val successColor = Color.rgb(83, 226, 151)
    private val warningColor = Color.rgb(255, 198, 92)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        root = FrameLayout(this).apply { setBackgroundColor(bgColor) }
        setContentView(root)
        showHome(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        showHome(intent)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
    }

    private fun showHome(incoming: Intent? = null) {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        configureSystemBars(false)
        destroyBrowser()
        root.removeAllViews()
        remoteFullscreen = false

        val incomingUri = incoming?.data
        val validDeepLink = incomingUri?.takeIf {
            it.scheme == "maquinavirtual" && it.host == "connect"
        }
        val deepUrl = validDeepLink?.getQueryParameter("url")
        val deepPassword = validDeepLink?.getQueryParameter("password")
        val deepResolution = validDeepLink?.getQueryParameter("resolution")
        val lastUrl = prefs.getString("last_url", "").orEmpty()
        val initialUrl = deepUrl ?: lastUrl
        val initialResolution = deepResolution ?: prefs.getString("last_resolution", "1600x720").orEmpty()

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            setBackgroundColor(bgColor)
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(30))
        }
        scroll.addView(content, ViewGroup.LayoutParams(-1, -2))
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))

        val brandRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val logo = TextView(this).apply {
            text = "MV"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            background = gradientRounded(
                intArrayOf(Color.rgb(108, 78, 255), Color.rgb(89, 118, 255)),
                18f
            )
            elevation = dp(6).toFloat()
        }
        brandRow.addView(logo, LinearLayout.LayoutParams(dp(54), dp(54)))

        val titleBlock = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        titleBlock.addView(label("Máquina Virtual", 23f, primaryTextColor, true))
        titleBlock.addView(label("Seu Linux na nuvem, direto no celular", 13f, mutedColor, false))
        brandRow.addView(titleBlock, LinearLayout.LayoutParams(0, -2, 1f))
        brandRow.addView(chip("V0.2", accent2Color, Color.rgb(18, 27, 49)))
        content.addView(brandRow)

        content.addView(space(24))

        val hasSession = isSafeSessionUrl(initialUrl)
        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = gradientRounded(
                intArrayOf(Color.rgb(29, 25, 61), Color.rgb(16, 27, 51), panelColor),
                24f,
                Color.rgb(58, 55, 102)
            )
            elevation = dp(5).toFloat()
        }
        hero.addView(
            label(
                if (hasSession) "●  SESSÃO RECEBIDA" else "●  PRONTO PARA CONECTAR",
                12f,
                if (hasSession) successColor else accent2Color,
                true
            )
        )
        hero.addView(space(10))
        hero.addView(label("Seu desktop, sem a cara crua do noVNC.", 27f, primaryTextColor, true))
        hero.addView(space(8))
        hero.addView(
            label(
                "O app usa a sessão HTTPS do Colab, esconde a interface técnica do visualizador e mantém os controles importantes acessíveis no celular.",
                14f,
                mutedColor,
                false
            )
        )
        hero.addView(space(16))

        val chips = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.START
        }
        chips.addView(chip("HTTPS", successColor, Color.rgb(14, 42, 36)))
        chips.addView(spaceW(8))
        chips.addView(chip(initialResolution.ifBlank { "1600x720" }, accent2Color, Color.rgb(22, 31, 58)))
        chips.addView(spaceW(8))
        chips.addView(chip("VNC local", mutedColor, Color.rgb(25, 30, 44)))
        hero.addView(chips)
        content.addView(hero)

        content.addView(space(22))
        content.addView(sectionTitle("CONEXÃO"))
        content.addView(space(10))

        val urlInput = field("URL HTTPS da sessão", initialUrl)
        content.addView(urlInput)
        content.addView(space(10))

        val passInput = field("Senha temporária", deepPassword.orEmpty(), password = true)
        content.addView(passInput)
        content.addView(space(10))

        val resolutionInput = field("Resolução", initialResolution.ifBlank { "1600x720" })
        content.addView(resolutionInput)
        content.addView(space(14))

        val connect = primaryButton("CONECTAR AO DESKTOP") {
            val rawUrl = urlInput.text.toString().trim()
            val password = passInput.text.toString()
            val resolution = resolutionInput.text.toString().trim().ifBlank { "1600x720" }
            if (!isSafeSessionUrl(rawUrl)) {
                toast("Use uma URL HTTPS válida da sessão.")
                return@primaryButton
            }
            prefs.edit()
                .putString("last_url", rawUrl)
                .putString("last_resolution", resolution)
                .apply()
            openRemote(rawUrl, password, resolution)
        }
        content.addView(connect, LinearLayout.LayoutParams(-1, dp(56)))

        content.addView(space(10))
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        val colabButton = secondaryButton("ABRIR COLAB") {
            openExternal("https://colab.research.google.com/github/Johnatafgfdgf/M-quina-virtual/blob/main/cloud/MaquinaVirtual.ipynb")
        }
        val browserButton = secondaryButton("NAVEGADOR") {
            val rawUrl = urlInput.text.toString().trim()
            if (isSafeSessionUrl(rawUrl)) {
                openExternal(normalizeNoVncUrl(rawUrl))
            } else {
                toast("Ainda não há uma sessão HTTPS válida.")
            }
        }
        actions.addView(colabButton, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginEnd = dp(5) })
        actions.addView(browserButton, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginStart = dp(5) })
        content.addView(actions)

        content.addView(space(24))
        content.addView(sectionTitle("COMO O APP PROTEGE A SESSÃO"))
        content.addView(space(10))
        content.addView(infoCard("VNC NÃO FICA PÚBLICO", "A porta 5900 continua presa ao localhost da máquina. Só a interface web HTTPS sai pelo túnel."))
        content.addView(space(10))
        content.addView(infoCard("SENHA NÃO É SALVA", "A senha temporária fica apenas na sessão atual do app. A URL pode ser lembrada para facilitar uma reconexão."))
        content.addView(space(10))
        content.addView(infoCard("CONTROLES MOBILE", "Teclado, modo de arrasto, ajuste de escala, tela cheia, senha e reconexão ficam por cima do desktop."))

        if (!deepUrl.isNullOrBlank() && isSafeSessionUrl(deepUrl)) {
            Handler(Looper.getMainLooper()).postDelayed({
                openRemote(
                    deepUrl,
                    deepPassword.orEmpty(),
                    deepResolution ?: "1600x720"
                )
            }, 350)
        }
    }

    private fun openRemote(rawUrl: String, password: String, resolution: String) {
        currentPassword = password
        currentBaseUrl = rawUrl.trimEnd('/')
        currentResolution = resolution
        allowedHost = Uri.parse(currentBaseUrl).host.orEmpty()
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        configureSystemBars(true)
        root.removeAllViews()
        remoteFullscreen = false

        val stage = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        root.addView(stage, FrameLayout.LayoutParams(-1, -1))

        val browser = WebView(this)
        webView = browser
        browser.setBackgroundColor(Color.BLACK)
        browser.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            builtInZoomControls = false
            displayZoomControls = false
            setSupportZoom(false)
            javaScriptCanOpenWindowsAutomatically = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            userAgentString = "$userAgentString MaquinaVirtual/0.2"
        }
        browser.isFocusable = true
        browser.isFocusableInTouchMode = true
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, false)
        browser.webChromeClient = WebChromeClient()
        browser.addJavascriptInterface(RemoteBridge(), "MaquinaVirtualNative")
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                val safe = uri.scheme == "https" && uri.host == allowedHost
                return !safe
            }

            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                updateRemoteStatus("Conectando…", warningColor)
            }

            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
                if (Uri.parse(url).host != allowedHost) return
                styleNoVnc(view)
                autoFillPassword(view, currentPassword)
                watchNoVncStatus(view)
                detectTunnelError(view)
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                super.onReceivedError(view, request, error)
                if (request.isForMainFrame) updateRemoteStatus("Falha de rede", warningColor)
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                super.onReceivedHttpError(view, request, errorResponse)
                if (request.isForMainFrame) updateRemoteStatus("HTTP ${errorResponse.statusCode}", warningColor)
            }
        }
        stage.addView(browser, FrameLayout.LayoutParams(-1, -1))

        topBar = buildRemoteTopBar()
        stage.addView(
            topBar,
            FrameLayout.LayoutParams(-1, dp(60), Gravity.TOP).apply {
                leftMargin = dp(10)
                rightMargin = dp(10)
                topMargin = dp(8)
            }
        )

        bottomDock = buildRemoteDock()
        stage.addView(
            bottomDock,
            FrameLayout.LayoutParams(-2, dp(70), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                bottomMargin = dp(12)
                leftMargin = dp(12)
                rightMargin = dp(12)
            }
        )

        browser.loadUrl(normalizeNoVncUrl(currentBaseUrl))
    }

    private fun buildRemoteTopBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = rounded(Color.argb(238, 10, 14, 25), 18f, Color.rgb(40, 50, 76))
            elevation = dp(8).toFloat()
        }

        bar.addView(iconButton("‹") { showHome() }, LinearLayout.LayoutParams(dp(46), dp(46)))

        val title = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), 0, dp(10), 0)
        }
        title.addView(label("Desktop remoto", 15f, primaryTextColor, true))
        statusLabel = label("● Conectando…", 11f, warningColor, false)
        title.addView(statusLabel)
        bar.addView(title, LinearLayout.LayoutParams(0, -2, 1f))

        bar.addView(chip(currentResolution, accent2Color, Color.rgb(20, 29, 53)))
        bar.addView(spaceW(7))
        bar.addView(iconButton("SENHA") { copyPassword() }, LinearLayout.LayoutParams(dp(72), dp(46)))
        bar.addView(spaceW(6))
        bar.addView(iconButton("↻") { webView?.reload() }, LinearLayout.LayoutParams(dp(46), dp(46)))
        return bar
    }

    private fun buildRemoteDock(): View {
        val dock = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(7), dp(8), dp(7))
            background = rounded(Color.argb(239, 13, 18, 31), 20f, Color.rgb(45, 56, 87))
            elevation = dp(10).toFloat()
        }
        dock.addView(dockButton("⌨", "Teclado") { showRemoteKeyboard() })
        dock.addView(dockButton("↔", "Mouse") { toggleDragMode() })
        dock.addView(dockButton("▣", "Ajustar") { fitDesktop() })
        dock.addView(dockButton("⛶", "Tela cheia") { toggleRemoteFullscreen() })
        dock.addView(dockButton("•••", "Mais") { showMoreMenu(dock) })
        return dock
    }

    private fun showRemoteKeyboard() {
        invokeNoVncButton(listOf("noVNC_keyboard_button")) { clicked ->
            if (!clicked) toast("O teclado do noVNC ainda não está pronto.")
            Handler(Looper.getMainLooper()).postDelayed({
                webView?.requestFocusFromTouch()
                val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                webView?.let { imm.showSoftInput(it, InputMethodManager.SHOW_IMPLICIT) }
            }, 180)
        }
    }

    private fun toggleDragMode() {
        invokeNoVncButton(listOf("noVNC_view_drag_button")) { clicked ->
            if (clicked) toast("Modo de mouse/arrasto alternado.")
            else toast("Controle de mouse ainda não está disponível.")
        }
    }

    private fun fitDesktop() {
        val js = """
            (function(){
              try {
                const resize = document.getElementById('noVNC_setting_resize');
                if (resize) {
                  resize.value = 'scale';
                  resize.dispatchEvent(new Event('change', {bubbles:true}));
                }
                window.dispatchEvent(new Event('resize'));
                return true;
              } catch(e) { return false; }
            })();
        """.trimIndent()
        webView?.evaluateJavascript(js) { result ->
            toast(if (result == "true") "Desktop ajustado à tela." else "Não foi possível ajustar agora.")
        }
    }

    private fun toggleRemoteFullscreen() {
        remoteFullscreen = !remoteFullscreen
        topBar?.visibility = if (remoteFullscreen) View.GONE else View.VISIBLE
        bottomDock?.visibility = if (remoteFullscreen) View.GONE else View.VISIBLE
        configureSystemBars(true)
        toast(if (remoteFullscreen) "Tela cheia. Deslize da borda para mostrar as barras do Android." else "Controles visíveis.")
    }

    private fun showMoreMenu(anchor: View) {
        PopupMenu(this, anchor).apply {
            menu.add("Abrir no navegador")
            menu.add("Copiar URL")
            menu.add("Copiar senha")
            menu.add("Forçar paisagem")
            menu.add("Usar retrato")
            menu.add("Desconectar")
            setOnMenuItemClickListener { item ->
                when (item.title.toString()) {
                    "Abrir no navegador" -> openExternal(normalizeNoVncUrl(currentBaseUrl))
                    "Copiar URL" -> copyText("URL da Máquina Virtual", currentBaseUrl, "URL copiada.")
                    "Copiar senha" -> copyPassword()
                    "Forçar paisagem" -> requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    "Usar retrato" -> requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                    "Desconectar" -> invokeNoVncButton(listOf("noVNC_disconnect_button")) { ok ->
                        if (!ok) toast("O botão de desconexão ainda não está disponível.")
                    }
                }
                true
            }
            show()
        }
    }

    private fun invokeNoVncButton(ids: List<String>, callback: (Boolean) -> Unit) {
        val selectors = ids.joinToString(",") { "document.getElementById('${it}')" }
        val js = """
            (function(){
              const candidates = [$selectors];
              for (const el of candidates) {
                if (el) { el.click(); return true; }
              }
              return false;
            })();
        """.trimIndent()
        webView?.evaluateJavascript(js) { callback(it == "true") } ?: callback(false)
    }

    private fun styleNoVnc(view: WebView) {
        val js = """
            (function(){
              if (!document.getElementById('mv-mobile-style')) {
                const style = document.createElement('style');
                style.id = 'mv-mobile-style';
                style.textContent = `
                  html, body { background:#05070d !important; margin:0 !important; overflow:hidden !important; }
                  #noVNC_control_bar_anchor, #noVNC_control_bar { opacity:0 !important; pointer-events:none !important; }
                  #noVNC_status { display:none !important; }
                  #noVNC_screen { background:#05070d !important; }
                  #noVNC_canvas { image-rendering:auto !important; }
                `;
                document.head.appendChild(style);
              }
              return true;
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun watchNoVncStatus(view: WebView) {
        val js = """
            (function(){
              if (window.__mvStatusWatch) return true;
              window.__mvStatusWatch = true;
              const send = () => {
                const el = document.getElementById('noVNC_status');
                const text = (el && el.textContent ? el.textContent : '').trim();
                if (text && window.MaquinaVirtualNative) window.MaquinaVirtualNative.status(text);
              };
              send();
              const target = document.getElementById('noVNC_status');
              if (target) new MutationObserver(send).observe(target, {childList:true, subtree:true, characterData:true});
              return true;
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun detectTunnelError(view: WebView) {
        val js = """
            (function(){
              const t = (document.body && document.body.innerText ? document.body.innerText : '');
              return /Error\s+1033|Cloudflare Tunnel error/i.test(t);
            })();
        """.trimIndent()
        view.evaluateJavascript(js) { result ->
            if (result == "true") updateRemoteStatus("Túnel indisponível", warningColor)
        }
    }

    private fun autoFillPassword(view: WebView, password: String) {
        if (password.isEmpty()) return
        val quoted = JSONObject.quote(password)
        val js = """
            (function(){
              const pw = $quoted;
              function tryFill(){
                const input = document.getElementById('noVNC_password_input') || document.querySelector('input[type=password]');
                if (!input) return false;
                input.value = pw;
                input.dispatchEvent(new Event('input', {bubbles:true}));
                const button = document.getElementById('noVNC_password_button') || input.closest('form')?.querySelector('button') || document.querySelector('button[type=submit]');
                if (button) button.click();
                return true;
              }
              if (!tryFill()) {
                let count = 0;
                const timer = setInterval(function(){
                  count++;
                  if (tryFill() || count > 30) clearInterval(timer);
                }, 350);
              }
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private inner class RemoteBridge {
        @JavascriptInterface
        fun status(value: String) {
            runOnUiThread {
                val text = value.trim().take(90)
                when {
                    text.contains("connected", ignoreCase = true) || text.contains("conectado", ignoreCase = true) ->
                        updateRemoteStatus("Conectado", successColor)
                    text.contains("disconnect", ignoreCase = true) || text.contains("desconect", ignoreCase = true) ->
                        updateRemoteStatus("Desconectado", warningColor)
                    text.contains("connecting", ignoreCase = true) || text.contains("conectando", ignoreCase = true) ->
                        updateRemoteStatus("Conectando…", warningColor)
                    text.isNotBlank() -> updateRemoteStatus(text, mutedColor)
                }
            }
        }
    }

    private fun updateRemoteStatus(text: String, color: Int) {
        statusLabel?.apply {
            this.text = "● $text"
            setTextColor(color)
        }
    }

    private fun normalizeNoVncUrl(raw: String): String {
        val uri = Uri.parse(raw)
        if (uri.path.orEmpty().contains("vnc.html")) return raw
        val base = raw.trimEnd('/')
        return "$base/vnc.html?autoconnect=true&resize=scale&reconnect=true&path=websockify"
    }

    private fun isSafeSessionUrl(raw: String): Boolean {
        return try {
            val uri = Uri.parse(raw)
            uri.scheme == "https" && !uri.host.isNullOrBlank()
        } catch (_: Exception) {
            false
        }
    }

    private fun copyPassword() {
        if (currentPassword.isEmpty()) {
            toast("Esta sessão não trouxe senha para o app.")
            return
        }
        copyText("Senha da Máquina Virtual", currentPassword, "Senha copiada.")
    }

    private fun copyText(label: String, value: String, toastText: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value))
        toast(toastText)
    }

    private fun openExternal(url: String) {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    private fun field(hintText: String, initial: String, password: Boolean = false): EditText {
        return EditText(this).apply {
            hint = hintText
            setHintTextColor(Color.rgb(104, 114, 144))
            setTextColor(primaryTextColor)
            textSize = 14f
            setText(initial)
            setPadding(dp(16), 0, dp(16), 0)
            setSingleLine(true)
            background = rounded(panelColor, 15f, borderColor)
            if (password) {
                inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
            }
            layoutParams = LinearLayout.LayoutParams(-1, dp(54))
        }
    }

    private fun primaryButton(textValue: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.05f
            background = gradientRounded(
                intArrayOf(Color.rgb(111, 78, 255), Color.rgb(92, 104, 255)),
                17f
            )
            elevation = dp(5).toFloat()
            isClickable = true
            isFocusable = true
            setOnClickListener { action() }
        }
    }

    private fun secondaryButton(textValue: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            setTextColor(primaryTextColor)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.04f
            background = rounded(panel2Color, 15f, borderColor)
            setOnClickListener { action() }
        }
    }

    private fun iconButton(textValue: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            setTextColor(primaryTextColor)
            textSize = if (textValue.length > 2) 10f else 23f
            typeface = Typeface.DEFAULT_BOLD
            background = rounded(Color.rgb(25, 31, 50), 14f, Color.rgb(48, 59, 88))
            setOnClickListener { action() }
        }
    }

    private fun dockButton(icon: String, caption: String, action: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(4), dp(14), dp(4))
            isClickable = true
            isFocusable = true
            addView(label(icon, 20f, Color.rgb(190, 198, 255), true))
            addView(label(caption, 10f, mutedColor, false))
            setOnClickListener { action() }
        }
    }

    private fun chip(textValue: String, textColor: Int, fill: Int): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            setTextColor(textColor)
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(11), dp(7), dp(11), dp(7))
            background = rounded(fill, 30f, Color.argb(100, 95, 110, 155))
        }
    }

    private fun infoCard(title: String, body: String): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(15), dp(16), dp(15))
            background = rounded(panelColor, 16f, Color.rgb(34, 42, 64))
            addView(label(title, 12f, Color.rgb(172, 185, 255), true))
            addView(space(5))
            addView(label(body, 13f, mutedColor, false))
        }
    }

    private fun sectionTitle(value: String): TextView = label(value, 12f, mutedColor, true).apply {
        letterSpacing = 0.08f
    }

    private fun label(value: String, size: Float, color: Int, bold: Boolean): TextView {
        return TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            setLineSpacing(0f, 1.12f)
            if (bold) typeface = Typeface.DEFAULT_BOLD
        }
    }

    private fun space(height: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(height))
    }

    private fun spaceW(width: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(dp(width), 1)
    }

    private fun rounded(fill: Int, radius: Float, stroke: Int? = null): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radius.toInt()).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }
    }

    private fun gradientRounded(colors: IntArray, radius: Float, stroke: Int? = null): GradientDrawable {
        return GradientDrawable(GradientDrawable.Orientation.TL_BR, colors).apply {
            cornerRadius = dp(radius.toInt()).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }
    }

    private fun configureSystemBars(remote: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (remote) controller.hide(WindowInsets.Type.systemBars())
                else controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (remote) {
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            } else {
                View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
        window.statusBarColor = bgColor
        window.navigationBarColor = bgColor
    }

    private fun destroyBrowser() {
        webView?.apply {
            removeJavascriptInterface("MaquinaVirtualNative")
            stopLoading()
            loadUrl("about:blank")
            clearHistory()
            destroy()
        }
        webView = null
        topBar = null
        bottomDock = null
        statusLabel = null
        currentPassword = ""
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        val wv = webView
        when {
            wv == null -> super.onBackPressed()
            remoteFullscreen -> {
                remoteFullscreen = false
                topBar?.visibility = View.VISIBLE
                bottomDock?.visibility = View.VISIBLE
            }
            else -> showHome()
        }
    }

    override fun onDestroy() {
        destroyBrowser()
        super.onDestroy()
    }
}
