# Máquina Virtual

Projeto Android + cloud para transformar uma sessão Linux temporária em um desktop remoto acessível pelo celular.

[![Android APK](https://github.com/Johnatafgfdgf/M-quina-virtual/actions/workflows/android.yml/badge.svg)](https://github.com/Johnatafgfdgf/M-quina-virtual/actions/workflows/android.yml)

## Estado atual

A base funcional já contém:

- app Android nativo em Kotlin;
- visualizador noVNC embutido em WebView;
- deep link `maquinavirtual://connect` para receber sessão + senha;
- notebook do Google Colab;
- LXQt + Xvfb + x11vnc;
- VNC limitado a `localhost`;
- noVNC/websockify;
- Cloudflare Quick Tunnel HTTPS;
- scripts de iniciar, parar e diagnosticar;
- build automático do APK no GitHub Actions.

## Iniciar

Abra o notebook:

**Google Colab:**

https://colab.research.google.com/github/Johnatafgfdgf/M-quina-virtual/blob/main/cloud/MaquinaVirtual.ipynb

Execute as células em ordem. No fim, o notebook mostra:

1. URL pública HTTPS;
2. senha temporária;
3. botão **ABRIR NO APP**;
4. alternativa para abrir pelo navegador.

## Arquitetura

```text
Google Colab / Linux runtime
        ↓
      Xvfb
        ↓
      LXQt
        ↓
 x11vnc (127.0.0.1)
        ↓
 noVNC + websockify (127.0.0.1)
        ↓
 Cloudflare Tunnel (HTTPS/WSS)
        ↓
 App Android "Máquina Virtual"
```

Veja os detalhes em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## APK

Cada alteração relevante no Android dispara `.github/workflows/android.yml`. Quando o workflow termina com sucesso, o APK de debug fica nos **Artifacts** da execução com o nome `Maquina-Virtual-debug`.

## Segurança

- a porta 5900 não é publicada diretamente;
- a senha é temporária e muda a cada sessão criada pelo notebook;
- a senha não é salva permanentemente pelo app;
- a interface remota usa HTTPS/WSS pelo túnel;
- não existe senha padrão `user/password`;
- não existe keep-alive para burlar encerramento de runtime.

## Limitações reais

Isto não transforma o Colab em uma VM permanente. O provedor pode limitar ou encerrar runtimes e desktop remoto conforme suas políticas e disponibilidade. O armazenamento local é efêmero por padrão, noVNC não transmite áudio e uma GPU CUDA disponível no runtime não implica aceleração 3D do desktop.

## Origem

O projeto reaproveita a ideia útil da `Maquina-v7`, mas substitui o fluxo de Guacamole quebrado por uma cadeia menor e verificável baseada em noVNC. As diferenças técnicas estão documentadas em `docs/ARCHITECTURE.md`.
