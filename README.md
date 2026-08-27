# ansible-windows

Automação de provisionamento de estações de trabalho Windows da Coopershoes via
**Ansible + WinRM**: pastas padrão, software base, agentes corporativos licenciados e o
ambiente legado do ERP **SafeTech** (Orant/Oracle 8, Oracle Client 10G, TNS, DLLs/PLLs e
fontes).

## Documentação

| Documento | Conteúdo |
|---|---|
| **[Instalação do servidor](docs/instalacao-servidor.md)** | Como colocar o projeto num servidor novo: dependências, venv do Ansible, `files/`, `.env`, vault, preparação das estações, estrutura do repositório |
| **[Execução das automações](docs/execucao-automacoes.md)** | Como rodar os playbooks, tags, `--limit`, logs, inventário do AD, depuração |

## Visão geral

O servidor de automação (`srvrsalmoxti01`, Ubuntu 24.04) conecta nas estações via WinRM
(NTLM, porta 5986) e executa playbooks modulares, que podem rodar isoladamente ou em
sequência pelos playbooks orquestradores.

```
playbooks/setup-completo.yml
  ├── tasks/windows/config-pastas.yml       C:\temp e C:\lixo
  ├── tasks/programas/install-software.yml  Chocolatey, Chrome, WinRAR, 7-Zip, Adobe Reader
  ├── tasks/programas/install-agentes.yml   AnyDesk, BitDefender, WatchGuard EDR, Microsoft 365
  └── playbooks/install-safetech.yml
        ├── tasks/sft/install-orant.yml         Oracle 8 legado → C:\orant
        ├── tasks/sft/edit-reg.yml              chave de registro 64BITS
        ├── tasks/sft/install-oracle-10g.yml    Oracle Client 10G + PATH/TNS_ADMIN
        ├── tasks/sft/mv-files-sft.yml          DLL/PLL/PLX do d2kwut60 + atalho
        ├── tasks/sft/mv-fonts.yml              fontes de código de barras
        ├── tasks/sft/mv-tns.yml                tnsnames.ora + tnsping COOPER
        └── tasks/sft/edit-reg.yml              reaplica o registro
```

Fora do orquestrador: [tasks/programas/install-zabbix.yml](tasks/programas/install-zabbix.yml)
(Zabbix Agent 2 + cadastro via API), executado sob demanda.

## Início rápido

```bash
cd /opt/ansible

# Testar conexão com uma estação
ansible windows -m ansible.windows.win_ping --ask-vault-pass --limit MTZ_TI10

# Provisionar uma estação nova por completo
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit MTZ_TI10

# Somente o ambiente do ERP SafeTech
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass --limit MTZ_MODM01
```

⚠️ Sem `--limit`, os playbooks rodam em **todas** as estações do inventário.

Detalhes, tags e mais exemplos em [docs/execucao-automacoes.md](docs/execucao-automacoes.md).

## Pré-requisitos

- Repositório clonado em `/opt/ansible` (há caminhos absolutos no código).
- Ansible instalado (venv em `/opt/ansible-venv`) com `pywinrm` e as coleções de
  [requirements.yml](requirements.yml).
- Instaladores presentes em `files/` — **não versionados**, copiados separadamente.
- `.env` com `LDAP_PASSWORD` e a senha do Ansible Vault disponíveis.
- WinRM HTTPS (5986) habilitado nas estações de destino.

Passo a passo completo em [docs/instalacao-servidor.md](docs/instalacao-servidor.md).

## Logs

| Local | Caminho |
|---|---|
| Na estação Windows | `C:\temp\logs-ansible\<etapa>.log` |
| No servidor | `logs/<HOSTNAME>/<etapa>.log` |
| Log global | `logs/ansible-execucao.log` |

## Segurança

- Credenciais das estações ficam em
  [inventory/group_vars/windows/vault.yml](inventory/group_vars/windows/vault.yml),
  criptografado com Ansible Vault. Nunca commitar a senha do vault nem o arquivo
  descriptografado.
- `.env` (senha de consulta ao AD) e `files/` (software licenciado) são ignorados pelo
  Git e distribuídos fora do repositório.
