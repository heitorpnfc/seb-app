# 📲 XVI SEB - Sistema de Check-in com QR Code

Aplicativo Flutter para realizar check-in de participantes via leitura de QR Code, registrando presença automaticamente em uma planilha do **Google Sheets**.  
Desenvolvido para o **XVI Simpósio de Engenharia Biomédica (SEB)**, integrando autenticação via **Google Service Account** e suporte a múltiplos dias de evento.

---

## 🚀 Funcionalidades

- 📷 **Leitura de QR Code** para identificar o participante.
- 🗓 **Seleção de dia** (Segunda, Terça, Quarta).
- ✅ Registro automático de presença na planilha.
- 🕒 **Carimbo de data e hora** no momento do check-in.
- 🔒 Bloqueio de duplicatas (não registra presença novamente para a mesma pessoa no mesmo dia).
- 🎨 Interface moderna com logos do evento.
- 📊 Integração completa com **Google Sheets API**.

---

## 🛠 Tecnologias Utilizadas

- **[Flutter](https://flutter.dev/)**
- **[Dart](https://dart.dev/)**
- **[Google Sheets API v4](https://developers.google.com/sheets/api)**
- **[Google Service Account](https://cloud.google.com/iam/docs/service-accounts)**
- **[mobile_scanner](https://pub.dev/packages/mobile_scanner)** para leitura de QR Codes

---

## 📋 Pré-requisitos

Antes de rodar o projeto, você precisa ter:

1. **Flutter** instalado ([guia de instalação](https://docs.flutter.dev/get-started/install))
2. Uma **conta no Google Cloud** com o **Sheets API** habilitado
3. Um **Service Account** com a chave JSON
4. Uma **planilha do Google Sheets** configurada com as abas:
   - `Segunda`
   - `Terca`
   - `Quarta`

---
