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
import android.text.InputType
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

    private var currentPassword = ""
    private var currentBaseUrl = ""
    private var currentResolution = "1600x720"
    private var allowedHost = ""
    private var remoteFullscreen = false

    private val handler = Handler(Looper.getMainLooper())
    private val prefs by lazy { getSharedPreferences("maquina_virtual", MODE_PRIVATE) }

    private val bg = Color.rgb(7, 10, 18)
    private val panel = Color.rgb(15, 20, 34)
    private val panel2 = Color.rgb(22, 29, 48)
    private val border = Color.rgb(44, 55, 84)
    private val text = Color.rgb(246, 248, 255)
    private val muted = Color.rgb(158, 168, 198)
    private val accent = Color.rgb(112, 83, 255)
    private val accent2 = Color.rgb(100, 145, 255)
    private val success = Color.rgb(83, 226, 151)
    private val warning = Color.rgb(255, 198, 92)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        root = FrameLayout(this).apply { setBackgroundColor(bg) }
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

        val deep = incoming?.data?.takeIf {
            it.scheme == "maquinavirtual" && it.host == "connect"
        }
        val deepUrl = deep?.getQueryParameter("url")?.trim().orEmpty()
        val deepPassword = deep?.getQueryParameter("password").orEmpty()
        val deepResolution = deep?.getQueryParameter("resolution")?.trim().orEmpty()

        if (isSafeSessionUrl(deepUrl)) {
            prefs.edit()
                .putString("last_url", deepUrl.trimEnd('/'))
                .putString("last_resolution", deepResolution.ifBlank { "1600x720" })
                .apply()
        }

        val initialUrl = if (isSafeSessionUrl(deepUrl)) {
            deepUrl.trimEnd('/')
        } else {
            prefs.getString("last_url", "").orEmpty()
        }
        val initialResolution = deepResolution.ifBlank {
            prefs.getString("last_resolution", "1600x720").orEmpty().ifBlank { "1600x720" }
        }

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            setBackgroundColor(bg)
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(26), dp(20), dp(32))
        }
        scroll.addView(content, ViewGroup.LayoutParams(-1, -2))
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val logo = TextView(this).apply {
            this.text = "MV"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 19f
            typeface = Typeface.DEFAULT_BOLD
            background = gradientRounded(
                intArrayOf(Color.rgb(111, 74, 255), Color.rgb(79, 116, 255)),
                18f
            )
        }
        header.addView(logo, LinearLayout.LayoutParams(dp(56), dp(56)))

        val title = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        title.addView(label("Máquina Virtual", 24f, text, true))
        title.addView(label("Desktop Linux remoto no celular", 13f, muted, false))
        header.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        header.addView(chip("V0.3", accent2, Color.rgb(19, 28, 50)))
        content.addView(header)

        content.addView(space(24))

        val sessionReady = isSafeSessionUrl(initialUrl)
        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = gradientRounded(
                intArrayOf(Color.rgb(29, 24, 58), Color.rgb(16, 27, 51), panel),
                24f,
                Color.rgb(59, 57, 104)
            )
        }
        hero.addView(label(
            if (sessionReady) "●  SESSÃO PRONTA" else "●  AGUARDANDO SESSÃO",
            12f,
            if (sessionReady) success else accent2,
            true
        ))
        hero.addView(space(10))
        hero.addView(label(
            if (sessionReady) "Seu desktop está pronto para abrir." else "Inicie uma máquina no Colab.",
            26f,
            text,
            true
        ))
        hero.addView(space(8))
        hero.addView(label(
            if (sessionReady) "O app guardou a URL desta sessão. Você pode voltar para esta tela sem perder o endereço do túnel."
            else "Quando o Colab gerar a sessão, toque em ABRIR NO APP. URL e resolução serão preenchidas automaticamente.",
            14f,
            muted,
            false
        ))
        hero.addView(space(16))
        val chips = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        chips.addView(chip("HTTPS", success, Color.rgb(14, 42, 36)))
        chips.addView(spaceW(8))
        chips.addView(chip(initialResolution, accent2, Color.rgb(22, 31, 58)))
        hero.addView(chips)
        content.addView(hero)

        content.addView(space(22))
        content.addView(sectionTitle("SESSÃO"))
        content.addView(space(10))

        val urlInput = field("URL HTTPS da sessão", initialUrl)
        val passInput = field("Senha temporária", deepPassword, true)
        val resolutionInput = field("Resolução", initialResolution)
        content.addView(urlInput)
        content.addView(space(10))
        content.addView(passInput)
        content.addView(space(10))
        content.addView(resolutionInput)
        content.addView(space(14))

        content.addView(primaryButton("CONECTAR AO DESKTOP") {
            val rawUrl = urlInput.text.toString().trim()
            val password = passInput.text.toString()
            val resolution = resolutionInput.text.toString().trim().ifBlank { "1600x720" }
            if (!isSafeSessionUrl(rawUrl)) {
                toast("Ainda não há uma URL HTTPS válida.")
                return@primaryButton
            }
            persistSession(rawUrl, resolution)
            openRemote(rawUrl, password, resolution)
        }, LinearLayout.LayoutParams(-1, dp(56)))

        content.addView(space(10))
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(secondaryButton("ABRIR COLAB") {
            openExternal("https://colab.research.google.com/github/Johnatafgfdgf/M-quina-virtual/blob/main/cloud/MaquinaVirtual.ipynb")
        }, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginEnd = dp(5) })
        row.addView(secondaryButton("ABRIR NO NAVEGADOR") {
            val typed = urlInput.text.toString().trim()
            val candidate = if (isSafeSessionUrl(typed)) typed else prefs.getString("last_url", "").orEmpty()
            if (isSafeSessionUrl(candidate)) {
                openExternal(normalizeNoVncUrl(candidate))
            } else {
                toast("Crie uma sessão no Colab primeiro.")
            }
        }, LinearLayout.LayoutParams(0, dp(50), 1f).apply { marginStart = dp(5) })
        content.addView(row)

        content.addView(space(24))
        content.addView(infoCard("VNC LOCAL", "A porta 5900 continua presa ao localhost. Só a interface HTTPS passa pelo túnel."))
        content.addView(space(10))
        content.addView(infoCard("URL LEMBRADA", "O app lembra apenas o endereço e a resolução. A senha temporária não é salva no aparelho."))

        if (isSafeSessionUrl(deepUrl)) {
            handler.postDelayed({
                openRemote(deepUrl, deepPassword, deepResolution.ifBlank { "1600x720" })
            }, 250)
        }
    }

    private fun persistSession(rawUrl: String, resolution: String) {
        prefs.edit()
            .putString("last_url", rawUrl.trimEnd('/'))
            .putString("last_resolution", resolution)
            .apply()
    }

    private fun openRemote(rawUrl: String, password: String, resolution: String) {
        currentPassword = password
        currentBaseUrl = rawUrl.trimEnd('/')
        currentResolution = resolution.ifBlank { "1600x720" }
        allowedHost = Uri.parse(currentBaseUrl).host.orEmpty()
        persistSession(currentBaseUrl, currentResolution)

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
            userAgentString = "$userAgentString MaquinaVirtual/0.3"
        }
        browser.isFocusable = true
        browser.isFocusableInTouchMode = true
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, false)
        browser.webChromeClient = WebChromeClient()
        browser.addJavascriptInterface(RemoteBridge(), "MaquinaVirtualNative")
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val u = request.url
                return !(u.scheme == "https" && u.host == allowedHost)
            }

            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                updateRemoteStatus("Conectando…", warning)
            }

            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
                if (Uri.parse(url).host != allowedHost) return
                autoFillPassword(view, currentPassword)
                handler.postDelayed({ styleNoVnc(view) }, 900)
                handler.postDelayed({ watchNoVnc(view) }, 1100)
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                super.onReceivedError(view, request, error)
                if (request.isForMainFrame) updateRemoteStatus("Falha de rede", warning)
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                super.onReceivedHttpError(view, request, errorResponse)
                if (request.isForMainFrame) updateRemoteStatus("HTTP ${errorResponse.statusCode}", warning)
            }
        }
        stage.addView(browser, FrameLayout.LayoutParams(-1, -1))

        topBar = buildTopBar()
        stage.addView(topBar, FrameLayout.LayoutParams(-1, dp(60), Gravity.TOP).apply {
            leftMargin = dp(10); rightMargin = dp(10); topMargin = dp(8)
        })

        bottomDock = buildDock()
        stage.addView(bottomDock, FrameLayout.LayoutParams(-2, dp(70), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = dp(12)
        })

        browser.loadUrl(normalizeNoVncUrl(currentBaseUrl))
    }

    private fun buildTopBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = rounded(Color.argb(238, 9, 13, 24), 18f, Color.rgb(42, 52, 79))
            elevation = dp(8).toFloat()
        }
        bar.addView(iconButton("‹") { showHome() }, LinearLayout.LayoutParams(dp(46), dp(46)))
        val title = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), 0, dp(10), 0)
        }
        title.addView(label("Desktop remoto", 15f, text, true))
        statusLabel = label("● Conectando…", 11f, warning, false)
        title.addView(statusLabel)
        bar.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        bar.addView(chip(currentResolution, accent2, Color.rgb(20, 29, 53)))
        bar.addView(spaceW(7))
        bar.addView(iconButton("SENHA") { copyPassword() }, LinearLayout.LayoutParams(dp(72), dp(46)))
        bar.addView(spaceW(6))
        bar.addView(iconButton("↻") { webView?.reload() }, LinearLayout.LayoutParams(dp(46), dp(46)))
        return bar
    }

    private fun buildDock(): View {
        val dock = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(7), dp(6), dp(7), dp(6))
            background = rounded(Color.argb(240, 12, 17, 30), 20f, Color.rgb(48, 58, 89))
            elevation = dp(10).toFloat()
        }
        dock.addView(dockButton("⌨", "Teclado") { showRemoteKeyboard() })
        dock.addView(dockButton("↔", "Mouse") { toggleDragMode() })
        dock.addView(dockButton("▣", "Ajustar") { fitDesktop() })
        dock.addView(dockButton("⛶", "Tela cheia") { toggleRemoteFullscreen() })
        dock.addView(dockButton("•••", "Mais") { showMoreMenu(dock) })
        return dock
    }

    private fun autoFillPassword(view: WebView, password: String) {
        if (password.isBlank()) return
        val quoted = JSONObject.quote(password)
        val js = """
            (function(){
              const pw=$quoted;
              let tries=0;
              const t=setInterval(function(){
                tries++;
                const input=document.getElementById('noVNC_password_input') || document.querySelector('input[type=password]');
                if(input){
                  input.value=pw;
                  input.dispatchEvent(new Event('input',{bubbles:true}));
                  const btn=document.getElementById('noVNC_password_button') || document.querySelector('#noVNC_credentials_dlg button') || input.closest('form')?.querySelector('button');
                  if(btn) btn.click();
                  clearInterval(t);
                } else if(tries>24){ clearInterval(t); }
              },350);
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun styleNoVnc(view: WebView) {
        val js = """
            (function(){
              if(!document.getElementById('mv-native-style')){
                const s=document.createElement('style');
                s.id='mv-native-style';
                s.textContent=`
                  html,body{margin:0!important;padding:0!important;background:#05070d!important;overflow:hidden!important;width:100%!important;height:100%!important;}
                  #noVNC_control_bar_anchor,#noVNC_control_bar,#noVNC_status_bar{display:none!important;}
                  #noVNC_screen{position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;margin:0!important;padding:0!important;background:#05070d!important;}
                  #noVNC_container{width:100%!important;height:100%!important;margin:0!important;padding:0!important;}
                  #noVNC_canvas{max-width:100vw!important;max-height:100vh!important;}
                  #noVNC_transition_text{color:#eef2ff!important;}
                `;
                document.head.appendChild(s);
              }
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun watchNoVnc(view: WebView) {
        val js = """
            (function(){
              if(window.__mvWatch) return;
              window.__mvWatch=true;
              setInterval(function(){
                let body=(document.body && document.body.innerText || '').toLowerCase();
                let status='';
                let el=document.getElementById('noVNC_status');
                if(el) status=(el.innerText||'').trim();
                if(body.includes('error 1033') || body.includes('cloudflare tunnel error')){
                  MaquinaVirtualNative.status('Túnel indisponível');
                }else if(status){
                  MaquinaVirtualNative.status(status);
                }else if(document.getElementById('noVNC_canvas')){
                  MaquinaVirtualNative.status('Conectado');
                }
              },900);
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun showRemoteKeyboard() {
        val w = webView ?: return
        w.evaluateJavascript("""
            (function(){
              const b=document.getElementById('noVNC_keyboard_button'); if(b) b.click();
              const i=document.getElementById('noVNC_keyboardinput') || document.querySelector('textarea');
              if(i){ i.focus(); i.click(); return true; }
              return false;
            })();
        """.trimIndent(), null)
        w.requestFocus()
        handler.postDelayed({
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(w, InputMethodManager.SHOW_IMPLICIT)
        }, 180)
    }

    private fun toggleDragMode() {
        webView?.evaluateJavascript("""
            (function(){
              const b=document.getElementById('noVNC_view_drag_button');
              if(b){ b.click(); return true; }
              return false;
            })();
        """.trimIndent(), null)
        toast("Modo de mouse alternado.")
    }

    private fun fitDesktop() {
        webView?.evaluateJavascript("""
            (function(){
              const c=document.getElementById('noVNC_canvas');
              if(c){ c.style.maxWidth='100vw'; c.style.maxHeight='100vh'; }
              window.dispatchEvent(new Event('resize'));
              return true;
            })();
        """.trimIndent(), null)
        toast("Desktop ajustado à tela.")
    }

    private fun toggleRemoteFullscreen() {
        remoteFullscreen = !remoteFullscreen
        topBar?.visibility = if (remoteFullscreen) View.GONE else View.VISIBLE
        bottomDock?.visibility = if (remoteFullscreen) View.GONE else View.VISIBLE
        configureSystemBars(true, remoteFullscreen)
        webView?.evaluateJavascript("window.dispatchEvent(new Event('resize'));", null)
    }

    private fun showMoreMenu(anchor: View) {
        PopupMenu(this, anchor).apply {
            menu.add("Abrir no navegador")
            menu.add("Copiar URL")
            menu.add("Copiar senha")
            menu.add("Reconectar")
            menu.add("Voltar ao início")
            setOnMenuItemClickListener { item ->
                when (item.title.toString()) {
                    "Abrir no navegador" -> openExternal(normalizeNoVncUrl(currentBaseUrl))
                    "Copiar URL" -> copyText("URL da Máquina Virtual", currentBaseUrl, "URL copiada.")
                    "Copiar senha" -> copyPassword()
                    "Reconectar" -> webView?.reload()
                    "Voltar ao início" -> showHome()
                }
                true
            }
            show()
        }
    }

    inner class RemoteBridge {
        @JavascriptInterface
        fun status(value: String?) {
            val clean = value.orEmpty().trim().take(80)
            handler.post {
                when {
                    clean.contains("túnel", true) || clean.contains("error", true) || clean.contains("failed", true) -> updateRemoteStatus(clean.ifBlank { "Falha" }, warning)
                    clean.contains("disconnect", true) -> updateRemoteStatus("Desconectado", warning)
                    clean.isNotBlank() -> updateRemoteStatus(if (clean.length > 28) "Conectado" else clean, success)
                }
            }
        }
    }

    private fun updateRemoteStatus(value: String, color: Int) {
        statusLabel?.apply {
            this.text = "● $value"
            setTextColor(color)
        }
    }

    private fun normalizeNoVncUrl(raw: String): String {
        val base = raw.substringBefore("/vnc.html").trimEnd('/')
        return "$base/vnc.html?autoconnect=true&resize=scale&reconnect=true&path=websockify"
    }

    private fun isSafeSessionUrl(raw: String): Boolean {
        if (raw.isBlank()) return false
        return try {
            val u = Uri.parse(raw)
            u.scheme == "https" && !u.host.isNullOrBlank()
        } catch (_: Exception) { false }
    }

    private fun openExternal(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            }
            startActivity(Intent.createChooser(intent, "Abrir com"))
        } catch (_: Exception) {
            toast("Não encontrei um navegador para abrir este link.")
        }
    }

    private fun copyPassword() {
        if (currentPassword.isBlank()) {
            toast("A senha desta sessão não está disponível no app.")
            return
        }
        copyText("Senha da Máquina Virtual", currentPassword, "Senha copiada.")
    }

    private fun copyText(label: String, value: String, message: String) {
        val cb = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cb.setPrimaryClip(ClipData.newPlainText(label, value))
        toast(message)
    }

    private fun field(hintText: String, initial: String, password: Boolean = false): EditText {
        return EditText(this).apply {
            hint = hintText
            setHintTextColor(Color.rgb(105, 115, 143))
            setTextColor(text)
            textSize = 14f
            setText(initial)
            setPadding(dp(16), 0, dp(16), 0)
            setSingleLine(true)
            background = rounded(panel, 15f, border)
            if (password) inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            layoutParams = LinearLayout.LayoutParams(-1, dp(54))
        }
    }

    private fun primaryButton(value: String, action: () -> Unit): TextView = TextView(this).apply {
        this.text = value
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 14f
        typeface = Typeface.DEFAULT_BOLD
        letterSpacing = 0.04f
        background = gradientRounded(intArrayOf(Color.rgb(111, 72, 255), Color.rgb(83, 108, 255)), 17f)
        setOnClickListener { action() }
    }

    private fun secondaryButton(value: String, action: () -> Unit): TextView = TextView(this).apply {
        this.text = value
        gravity = Gravity.CENTER
        setTextColor(text)
        textSize = 12f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(panel2, 15f, border)
        setOnClickListener { action() }
    }

    private fun iconButton(value: String, action: () -> Unit): TextView = TextView(this).apply {
        this.text = value
        gravity = Gravity.CENTER
        setTextColor(text)
        textSize = if (value.length > 2) 10f else 24f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(panel2, 13f, border)
        setOnClickListener { action() }
    }

    private fun dockButton(icon: String, title: String, action: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(11), dp(3), dp(11), dp(3))
            addView(label(icon, 19f, Color.rgb(190, 196, 255), true))
            addView(label(title, 10f, muted, false))
            setOnClickListener { action() }
        }
    }

    private fun chip(value: String, color: Int, fill: Int): TextView = TextView(this).apply {
        this.text = value
        gravity = Gravity.CENTER
        setTextColor(color)
        textSize = 11f
        typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(12), dp(7), dp(12), dp(7))
        background = rounded(fill, 20f, Color.rgb(47, 58, 88))
    }

    private fun infoCard(title: String, body: String): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(15), dp(16), dp(15))
        background = rounded(panel, 16f, Color.rgb(34, 42, 65))
        addView(label(title, 12f, Color.rgb(195, 200, 255), true))
        addView(space(5))
        addView(label(body, 13f, muted, false))
    }

    private fun sectionTitle(value: String): TextView = label(value, 12f, muted, true).apply { letterSpacing = 0.08f }

    private fun label(value: String, size: Float, color: Int, bold: Boolean): TextView = TextView(this).apply {
        this.text = value
        textSize = size
        setTextColor(color)
        setLineSpacing(0f, 1.12f)
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun rounded(fill: Int, radius: Float, stroke: Int? = null): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(fill)
        cornerRadius = dp(radius.toInt()).toFloat()
        if (stroke != null) setStroke(dp(1), stroke)
    }

    private fun gradientRounded(colors: IntArray, radius: Float, stroke: Int? = null): GradientDrawable =
        GradientDrawable(GradientDrawable.Orientation.TL_BR, colors).apply {
            cornerRadius = dp(radius.toInt()).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }

    private fun space(h: Int): View = View(this).apply { layoutParams = LinearLayout.LayoutParams(1, dp(h)) }
    private fun spaceW(w: Int): View = View(this).apply { layoutParams = LinearLayout.LayoutParams(dp(w), 1) }

    private fun configureSystemBars(remote: Boolean, hideNavigation: Boolean = false) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { c ->
                c.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (remote) c.hide(WindowInsets.Type.statusBars()) else c.show(WindowInsets.Type.statusBars())
                if (hideNavigation) c.hide(WindowInsets.Type.navigationBars()) else c.show(WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = when {
                remote && hideNavigation -> View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                remote -> View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                else -> View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
        window.statusBarColor = bg
        window.navigationBarColor = bg
    }

    private fun destroyBrowser() {
        webView?.apply {
            stopLoading()
            loadUrl("about:blank")
            clearHistory()
            removeAllViews()
            destroy()
        }
        webView = null
        topBar = null
        bottomDock = null
        statusLabel = null
    }

    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (webView != null) showHome() else super.onBackPressed()
    }

    override fun onDestroy() {
        destroyBrowser()
        super.onDestroy()
    }
}
