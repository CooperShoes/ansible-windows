# ansible-windows

Automação de provisionamento de estações de trabalho Windows da Coopershoes via **Ansible + WinRM**: instalação de software base, agentes corporativos licenciados e do ambiente legado do ERP **SafeTech** (Orant/Oracle 8, Oracle Client 10G, TNS, DLLs/PLLs e fontes).

## Visão geral

O projeto orquestra a configuração completa de uma estação Windows a partir do servidor de automação (`srvrsalmoxti01`), conectando via WinRM (NTLM, porta 5986) e executando playbooks organizados em módulos independentes que podem ser rodados isoladamente ou em sequência através do playbook orquestrador.

## Estrutura do repositório

```
ansible-windows/
├── ansible.cfg                     # Configuração do Ansible (inventory, WinRM timeouts)
├── inventory/
│   ├── hosts.yml                   # Inventário de hosts Windows (grupos: estacoes_modelagem, estacoes_ti)
│   └── group_vars/
│       └── windows/
│           └── vault.yml           # Credenciais do usuário admin (criptografado com Ansible Vault)
├── playbooks/
│   ├── setup-completo.yml          # Orquestra: pastas → software base → agentes → SafeTech
│   └── install-safetech.yml        # Orquestra: Orant → Oracle 10G → TNS → arquivos ERP → fontes
└── tasks/
    ├── config-pastas.yml           # Cria C:\temp e C:\lixo
    ├── install-software.yml        # Chocolatey, Google Chrome, WinRAR, 7-Zip, Adobe Reader
    ├── install-agentes.yml         # AnyDesk, BitDefender, WatchGuard EDR, Microsoft 365 (ODT)
    └── sft/                        # Ambiente legado do ERP SafeTech
        ├── install-orant.yml       # Oracle 8 legado (Orant)
        ├── install-oracle-10g.yml  # Oracle Client 10G
        ├── mv-tns.yml              # Distribuição do tnsnames.ora
        ├── mv-files-sft.yml        # DLLs/PLLs (d2kwut60) e atalho do sistema
        ├── mv-fonts.yml            # Instalação de fontes customizadas
        └── edit-reg.yml            # Aplicação da chave de registro 64BITS
```

## Pré-requisitos

- Ansible instalado no servidor de automação (`srvrsalmoxti01`)
- Coleções `ansible.windows` e `community.windows`
- WinRM habilitado nas estações Windows de destino, com HTTPS na porta 5986
- Instaladores de terceiros disponíveis em `/opt/ansible/files/instaladores` e `/opt/ansible/files/sistema` (não versionados neste repositório — ver `.gitignore`)
- Ansible Vault configurado para descriptografar `inventory/group_vars/windows/vault.yml`

Instalar as coleções necessárias:

```bash
ansible-galaxy collection install ansible.windows community.windows
```

## Inventário

Os hosts são organizados em dois grupos dentro de `windows`:

- **estacoes_modelagem** — estações do setor de modelagem
- **estacoes_ti** — estações do setor de TI

A conexão usa WinRM com autenticação NTLM e validação de certificado desabilitada (ambiente interno). As credenciais (`vault_win_admin_user` / `vault_win_admin_pass`) ficam no vault criptografado.

## Uso

Executar o provisionamento completo em todas as estações do inventário:

```bash
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass
```

Executar apenas a instalação do ambiente SafeTech:

```bash
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass
```

Executar uma task específica isoladamente (ex.: apenas software base):

```bash
ansible-playbook tasks/install-software.yml --ask-vault-pass
```

Limitar a execução a um host ou grupo específico:

```bash
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit MTZ_TI10
```

Usar tags para pular pacotes opcionais (ex.: 7-Zip, Adobe Reader):

```bash
ansible-playbook tasks/install-software.yml --ask-vault-pass --skip-tags opcional
```

## O que cada etapa faz

| Etapa | Playbook/Task | Ação |
|---|---|---|
| 1 | `config-pastas.yml` | Cria diretórios padrão (`C:\temp`, `C:\lixo`) |
| 2 | `install-software.yml` | Instala Chocolatey e software base (Chrome, WinRAR, 7-Zip, Adobe Reader) |
| 3 | `install-agentes.yml` | Instala AnyDesk, BitDefender, WatchGuard EDR e Microsoft 365 Apps via ODT |
| 4 | `install-safetech.yml` | Instala e configura o ambiente completo do ERP SafeTech (Orant, Oracle 10G, TNS, DLLs, fontes) |

Cada task registra o resultado de suas ações principais e imprime um relatório de sucesso/falha ao final (bloco `debug` com resumo por componente), facilitando a auditoria da execução em massa.

## Segurança

- Credenciais de acesso às estações ficam em `inventory/group_vars/windows/vault.yml`, criptografado via Ansible Vault — nunca commitar a senha do vault nem versionar o arquivo descriptografado.
- Instaladores proprietários/licenciados (`.msi`, `.exe`, `.dll`, `.plx`, `.gif`) e a pasta `files/` são ignorados pelo Git (`.gitignore`) e devem ser distribuídos separadamente para o servidor de automação.

## Roadmap / possíveis melhorias

- Migrar variáveis sensíveis adicionais (nomes de instaladores) para `group_vars`
- Adicionar handlers para reinício de serviços quando necessário
- Cobrir validação pós-instalação (ex.: checar versão instalada de cada agente)