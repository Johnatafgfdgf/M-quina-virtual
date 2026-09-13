package com.johnata.maquinavirtual

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
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
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

class MainActivity : Activity() {

    private lateinit var root: FrameLayout
    private var webView: WebView? = null
    private var currentPassword: String = ""
    private val prefs by lazy { getSharedPreferences("maquina_virtual", MODE_PRIVATE) }

    private val bgColor = Color.rgb(9, 11, 18)
    private val panelColor = Color.rgb(18, 22, 34)
    private val panel2Color = Color.rgb(25, 30, 46)
    private val primaryTextColor = Color.rgb(244, 246, 255)
    private val mutedColor = Color.rgb(155, 164, 190)
    private val accentColor = Color.rgb(126, 92, 255)
    private val accent2Color = Color.rgb(72, 211, 255)
    private val successColor = Color.rgb(82, 214, 146)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        root = FrameLayout(this).apply { setBackgroundColor(bgColor) }
        setContentView(root)
        configureSystemBars(false)
        showHome(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        showHome(intent)
    }

    private fun showHome(incoming: Intent? = null) {
        webView?.destroy()
        webView = null
        currentPassword = ""
        configureSystemBars(false)
        root.removeAllViews()

        val scroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(28), dp(22), dp(28))
        }
        scroll.addView(
            content,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))

        val brandRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val mark = TextView(this).apply {
            text = "M"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            background = rounded(accentColor, 18f)
        }
        brandRow.addView(mark, LinearLayout.LayoutParams(dp(54), dp(54)))

        val brandText = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        brandText.addView(label("MÁQUINA VIRTUAL", 22f, primaryTextColor, true))
        brandText.addView(label("Seu desktop Linux remoto no celular", 13f, mutedColor, false))
        brandRow.addView(brandText, LinearLayout.LayoutParams(0, -2, 1f))
        content.addView(brandRow)

        content.addView(space(26))

        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = gradientPanel()
        }
        hero.addView(label("●  PRONTO PARA CONECTAR", 12f, successColor, true))
        hero.addView(space(12))
        hero.addView(label("Uma janela para a sua máquina na nuvem.", 28f, primaryTextColor, true))
        hero.addView(space(8))
        hero.addView(
            label(
                "Inicie a sessão no notebook e abra o link no app. A porta VNC fica local e somente a interface HTTPS é publicada.",
                14f,
                mutedColor,
                false
            )
        )
        content.addView(hero)

        content.addView(space(22))
        content.addView(label("CONEXÃO", 12f, mutedColor, true))
        content.addView(space(10))

        val incomingUri = incoming?.data
        val validDeepLink = incomingUri?.takeIf {
            it.scheme == "maquinavirtual" && it.host == "connect"
        }
        val deepUrl = validDeepLink?.getQueryParameter("url")
        val deepPassword = validDeepLink?.getQueryParameter("password")

        val urlInput = field(
            "URL HTTPS da sessão",
            deepUrl ?: prefs.getString("last_url", "").orEmpty()
        )
        content.addView(urlInput)
        content.addView(space(10))

        val passInput = field("Senha temporária", deepPassword.orEmpty(), password = true)
        content.addView(passInput)
        content.addView(space(14))

        val connect = actionButton("ABRIR DESKTOP", accentColor) {
            val rawUrl = urlInput.text.toString().trim()
            val password = passInput.text.toString()
            if (!isSafeSessionUrl(rawUrl)) {
                toast("Use uma URL HTTPS válida da sessão.")
                return@actionButton
            }
            prefs.edit().putString("last_url", rawUrl).apply()
            openRemote(normalizeNoVncUrl(rawUrl), password)
        }
        content.addView(connect, LinearLayout.LayoutParams(-1, dp(54)))

        content.addView(space(10))
        val notebook = actionButton("INICIAR / GERENCIAR SESSÃO", panel2Color) {
            openExternal(
                "https://colab.research.google.com/github/Johnatafgfdgf/M-quina-virtual/blob/main/cloud/MaquinaVirtual.ipynb"
            )
        }
        content.addView(notebook, LinearLayout.LayoutParams(-1, dp(50)))

        content.addView(space(24))
        content.addView(
            infoCard(
                "CONEXÃO SEGURA",
                "VNC escuta apenas em localhost. O app recebe uma URL HTTPS temporária do túnel."
            )
        )
        content.addView(space(10))
        content.addView(
            infoCard(
                "SESSÃO TEMPORÁRIA",
                "O runtime pode ser encerrado pelo provedor. Arquivos importantes devem ser salvos em armazenamento persistente."
            )
        )
        content.addView(space(10))
        content.addView(
            infoCard(
                "MODO MOBILE",
                "O visualizador usa noVNC dentro do app com toque, teclado e redimensionamento para a tela do celular."
            )
        )

        if (!deepUrl.isNullOrBlank() && isSafeSessionUrl(deepUrl)) {
            Handler(Looper.getMainLooper()).postDelayed({
                openRemote(normalizeNoVncUrl(deepUrl), deepPassword.orEmpty())
            }, 300)
        }
    }

    private fun openRemote(url: String, password: String) {
        currentPassword = password
        configureSystemBars(true)
        root.removeAllViews()

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
        }

        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
            setBackgroundColor(bgColor)
        }

        toolbar.addView(
            compactButton("‹") { showHome() },
            LinearLayout.LayoutParams(dp(48), dp(44))
        )

        val title = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), 0, dp(8), 0)
        }
        title.addView(label("Desktop remoto", 15f, primaryTextColor, true))
        title.addView(label("● conexão protegida por HTTPS", 11f, successColor, false))
        toolbar.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        toolbar.addView(
            compactButton("SENHA") { copyPassword() },
            LinearLayout.LayoutParams(dp(72), dp(44))
        )
        toolbar.addView(
            compactButton("↻") { webView?.reload() },
            LinearLayout.LayoutParams(dp(48), dp(44))
        )

        container.addView(toolbar, LinearLayout.LayoutParams(-1, dp(60)))

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
            javaScriptCanOpenWindowsAutomatically = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            userAgentString = "$userAgentString MaquinaVirtual/0.1"
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, false)
        browser.webChromeClient = WebChromeClient()
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                return request.url.scheme != "https"
            }

            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
                if (currentPassword.isNotEmpty()) {
                    autoFillPassword(view, currentPassword)
                }
            }
        }
        browser.loadUrl(url)
        container.addView(browser, LinearLayout.LayoutParams(-1, 0, 1f))

        root.addView(container, FrameLayout.LayoutParams(-1, -1))
    }

    private fun autoFillPassword(view: WebView, password: String) {
        val quoted = JSONObject.quote(password)
        val js = """
            (function(){
              const pw = $quoted;
              function tryFill(){
                const input = document.getElementById('noVNC_password_input') ||
                              document.querySelector('input[type=password]');
                if (!input) return false;
                input.value = pw;
                input.dispatchEvent(new Event('input', {bubbles:true}));
                const button = document.getElementById('noVNC_password_button') ||
                               input.closest('form')?.querySelector('button') ||
                               document.querySelector('button[type=submit]');
                if (button) button.click();
                return true;
              }
              if (!tryFill()) {
                let count = 0;
                const timer = setInterval(function(){
                  count++;
                  if (tryFill() || count > 20) clearInterval(timer);
                }, 500);
              }
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
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
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(
            ClipData.newPlainText("Senha da Máquina Virtual", currentPassword)
        )
        toast("Senha copiada.")
    }

    private fun openExternal(url: String) {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    private fun field(
        hintText: String,
        initial: String,
        password: Boolean = false
    ): EditText {
        return EditText(this).apply {
            hint = hintText
            setHintTextColor(Color.rgb(104, 113, 139))
            setTextColor(primaryTextColor)
            textSize = 14f
            setText(initial)
            setPadding(dp(16), 0, dp(16), 0)
            setSingleLine(true)
            background = rounded(panelColor, 14f, Color.rgb(45, 53, 76))
            if (password) {
                inputType = android.text.InputType.TYPE_CLASS_TEXT or
                    android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
            }
            layoutParams = LinearLayout.LayoutParams(-1, dp(54))
        }
    }

    private fun actionButton(
        textValue: String,
        color: Int,
        action: () -> Unit
    ): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.06f
            background = rounded(color, 16f)
            isClickable = true
            isFocusable = true
            setOnClickListener { action() }
        }
    }

    private fun compactButton(textValue: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            setTextColor(primaryTextColor)
            textSize = if (textValue.length > 2) 10f else 24f
            typeface = Typeface.DEFAULT_BOLD
            background = rounded(panel2Color, 12f)
            setOnClickListener { action() }
        }
    }

    private fun infoCard(title: String, body: String): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(15), dp(16), dp(15))
            background = rounded(panelColor, 15f, Color.rgb(33, 39, 58))
            addView(label(title, 12f, accent2Color, true))
            addView(space(5))
            addView(label(body, 13f, mutedColor, false))
        }
    }

    private fun label(
        value: String,
        size: Float,
        color: Int,
        bold: Boolean
    ): TextView {
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

    private fun rounded(
        fill: Int,
        radius: Float,
        stroke: Int? = null
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(fill)
            cornerRadius = dp(radius.toInt()).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }
    }

    private fun gradientPanel(): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(Color.rgb(34, 29, 67), Color.rgb(18, 28, 51), panelColor)
        ).apply {
            cornerRadius = dp(22).toFloat()
        }
    }

    private fun configureSystemBars(remote: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (remote) {
                    controller.hide(WindowInsets.Type.statusBars())
                } else {
                    controller.show(WindowInsets.Type.statusBars())
                }
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (remote) {
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            } else {
                View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
        window.statusBarColor = bgColor
        window.navigationBarColor = bgColor
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        val wv = webView
        when {
            wv == null -> super.onBackPressed()
            wv.canGoBack() -> wv.goBack()
            else -> showHome()
        }
    }

    override fun onDestroy() {
        webView?.destroy()
        webView = null
        super.onDestroy()
    }
}
