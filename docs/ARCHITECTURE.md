# Arquitetura — Máquina Virtual

## 1. Objetivo

O projeto separa o runtime remoto do cliente Android. O runtime pode existir em um ambiente Linux temporário (inicialmente Google Colab), enquanto o app Android funciona como painel e visualizador.

## 2. Caminho da imagem e entrada

```text
LXQt
 ↓
Xvfb (:10)
 ↓
x11vnc (127.0.0.1:5900)
 ↓
websockify/noVNC (127.0.0.1:6080)
 ↓
Cloudflare Quick Tunnel (HTTPS/WSS)
 ↓
WebView seguro do app Android
```

A porta VNC não é publicada diretamente. O único endpoint público é HTTPS/WSS.

## 3. Provisionamento

`cloud/scripts/install.sh` instala os componentes do desktop. `start.sh` cria a sessão, gera `/tmp/maquina-virtual/session.json` e devolve um deep link no formato:

```text
maquinavirtual://connect?url=<https-url>&password=<senha-temporaria>
```

O aplicativo registra esse esquema no AndroidManifest e abre o visualizador automaticamente.

## 4. Segurança atual

- senha VNC temporária por sessão;
- senha limitada a 8 caracteres por compatibilidade com autenticação VNC clássica;
- `x11vnc -localhost`;
- `websockify` vinculado a `127.0.0.1`;
- WebView aceita somente URLs HTTPS no fluxo de navegação;
- credencial da sessão fica apenas em memória no app, não é salva em SharedPreferences;
- URL pode ser salva localmente para reconexão.

## 5. O que foi removido da Maquina-v7

- autenticação JSON incorreta do Apache Guacamole;
- chave estática de autenticação;
- credenciais padrão `user/password`;
- VNC potencialmente acessível além do necessário;
- keep-alive apresentado como proteção contra desligamento;
- mensagens que sugeriam aceleração gráfica sem uma cadeia real de renderização pela GPU.

## 6. Limitações atuais

- o app não cria um runtime Colab silenciosamente; autenticação e início do runtime pertencem ao Google Colab;
- noVNC não transporta áudio;
- GPU CUDA disponível no runtime não significa aceleração 3D automática do Xvfb;
- o armazenamento local do runtime é efêmero;
- Quick Tunnels são temporários.

## 7. Próximos módulos

- `SessionProvider` para permitir provedores além do Colab;
- armazenamento persistente opcional;
- resolução adaptativa baseada no viewport do Android;
- cliente remoto alternativo com áudio;
- telemetria local de CPU/RAM/GPU;
- release signing;
- testes instrumentados Android;
- assets finais de marca e splash.
