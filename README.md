# Máquina Virtual

Projeto Android + cloud para transformar uma sessão Linux temporária em um desktop remoto acessível pelo celular.

> Status: desenvolvimento ativo. A infraestrutura do Maquina-v7 está sendo migrada e corrigida aqui.

## Arquitetura

```text
Google Colab / Linux runtime
        ↓
      Xvfb
        ↓
      LXQt
        ↓
 x11vnc (localhost)
        ↓
 noVNC + websockify
        ↓
 Cloudflare Tunnel (HTTPS)
        ↓
 App Android "Máquina Virtual"
```

## Objetivos

- app Android nativo para celular;
- desktop Linux remoto acessível dentro do próprio app;
- senha de sessão temporária e VNC nunca exposto diretamente à internet;
- conexão por deep link `maquinavirtual://connect`;
- diagnóstico e logs;
- armazenamento persistente opcional;
- build automático de APK pelo GitHub Actions.

## Importante

Este projeto não transforma o Google Colab em uma VM permanente. O provedor pode limitar ou encerrar runtimes e desktop remoto conforme suas políticas e disponibilidade. O projeto não inclui mecanismos para contornar limites de sessão ou anti-idle.
