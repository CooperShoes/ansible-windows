# Instalação do servidor de automação

Guia para colocar este projeto em funcionamento em um **servidor novo** (controlador Ansible).

Ambiente de referência atualmente em produção:

| Item | Valor |
|---|---|
| Sistema operacional | Ubuntu 24.04 LTS |
| Python | 3.12 |
| Ansible | `ansible` 14.3.0 (`ansible-core` 2.21.3) |
| Instalação do Ansible | virtualenv em `/opt/ansible-venv` |
| Repositório | `/opt/ansible` |
| Conexão com as estações | WinRM sobre HTTPS (porta 5986), autenticação NTLM |

> **Importante:** o caminho `/opt/ansible` é obrigatório. Existem caminhos absolutos no
> código (`atualizar-inventory.sh` e `tasks/programas/install-zabbix.yml`) que apontam
> para `/opt/ansible/...`. Clonar em outro diretório exige ajustar esses arquivos.

---

## 1. Pacotes do sistema operacional

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip git ldap-utils
```

- `ldap-utils` fornece o `ldapsearch`, usado por `atualizar-inventory.sh` para gerar o
  inventário a partir do Active Directory.

## 2. Clonar o repositório

```bash
sudo git clone https://github.com/CooperShoes/ansible-windows.git /opt/ansible
cd /opt/ansible
```

## 3. Criar o virtualenv e instalar o Ansible

```bash
sudo python3 -m venv /opt/ansible-venv
sudo /opt/ansible-venv/bin/pip install --upgrade pip
sudo /opt/ansible-venv/bin/pip install "ansible==14.3.0" pywinrm requests-ntlm requests-credssp
```

- `pywinrm` + `requests-ntlm` são obrigatórios: sem eles o Ansible não consegue abrir
  conexão WinRM com as estações Windows.
- O pacote `ansible` (não apenas `ansible-core`) já traz as coleções usadas pelo projeto
  (`ansible.windows`, `community.windows`, `chocolatey.chocolatey`).

Deixe os binários acessíveis no PATH da sessão (opcional, mas recomendado):

```bash
echo 'export PATH="/opt/ansible-venv/bin:$PATH"' | sudo tee /etc/profile.d/ansible-venv.sh
source /etc/profile.d/ansible-venv.sh
```

Sem isso, todos os comandos precisam ser chamados pelo caminho completo:
`/opt/ansible-venv/bin/ansible-playbook ...`

## 4. Instalar as coleções (se necessário)

Se a instalação tiver sido feita apenas com `ansible-core`, instale as coleções
declaradas em [requirements.yml](../requirements.yml):

```bash
/opt/ansible-venv/bin/ansible-galaxy collection install -r /opt/ansible/requirements.yml
```

Conferir o que está instalado:

```bash
/opt/ansible-venv/bin/ansible-galaxy collection list | grep -E "ansible.windows|community.windows|chocolatey"
```

## 5. Copiar os instaladores (`files/`)

**A pasta `files/` não é versionada no Git** (ver [.gitignore](../.gitignore)) — contém
software licenciado e binários grandes. Ela precisa ser copiada manualmente do servidor
antigo ou do repositório de mídias da TI.

Estrutura esperada:

```
files/
├── instaladores/
│   ├── AnyDesk.exe
│   ├── WatchGuard Endpoint Agent.msi
│   ├── setupdownloader_[...base64...].exe        # instalador BitDefender GravityZone
│   ├── zabbix_agent2-7.4.13-windows-amd64-openssl.msi
│   └── office365/
│       ├── setup.exe                             # Office Deployment Tool
│       └── configuration.xml
└── sistema/
    ├── orant/orant.zip                           # Oracle 8 legado (Orant)
    ├── oracle/
    │   ├── client-oracle-10g.zip
    │   └── install-oracle-10g.bat
    ├── tns/TNSNAMES.ORA
    ├── fonts/*.ttf *.otf                         # fontes de código de barras e Courier
    └── files-sft/
        ├── d2kwut60.dll
        ├── D2KWUT60.pll
        ├── D2KWUT60.plx
        ├── 64BITS.reg
        ├── SISTEMAS.lnk
        └── XERPoratoolsBINifrun60.EXE.txt
```

Exemplo de cópia a partir do servidor antigo:

```bash
rsync -av --progress root@servidor-antigo:/opt/ansible/files/ /opt/ansible/files/
```

> O nome do instalador do BitDefender contém colchetes e uma string base64 e está fixado
> na variável `bitdefender_installer` em
> [tasks/programas/install-agentes.yml](../tasks/programas/install-agentes.yml). Se um
> pacote novo for baixado do GravityZone, o nome do arquivo muda e a variável precisa
> ser atualizada.

## 6. Configurar o `.env` (consulta ao Active Directory)

O arquivo `.env` guarda a senha da conta usada pelo `ldapsearch`. **Não é versionado.**

```bash
sudo tee /opt/ansible/.env > /dev/null <<'EOF'
LDAP_PASSWORD=senha-da-conta-de-consulta-ad
EOF
sudo chmod 600 /opt/ansible/.env
```

O servidor LDAP, a conta e a base de busca estão fixados no topo de
[atualizar-inventory.sh](../atualizar-inventory.sh):

```
LDAP_SERVER=ldap://192.168.0.2
LDAP_USER=admin.vitor@coopershoes.com.br
LDAP_BASE=DC=coopershoes,DC=com,DC=br
```

Ajuste esses valores se o servidor de AD ou a conta de serviço mudarem.

## 7. Configurar a senha do Ansible Vault

As credenciais de administrador das estações ficam criptografadas em
[inventory/group_vars/windows/vault.yml](../inventory/group_vars/windows/vault.yml)
(Ansible Vault, AES256), nas variáveis:

- `vault_win_admin_user`
- `vault_win_admin_pass`

A senha do vault **não está no repositório** e deve ser obtida com a equipe de TI. Para
testar se a senha está correta:

```bash
cd /opt/ansible
/opt/ansible-venv/bin/ansible-vault view inventory/group_vars/windows/vault.yml
```

Para evitar digitar a senha a cada execução, crie um arquivo de senha fora do repositório:

```bash
sudo install -m 600 /dev/null /root/.vault_pass
sudo vi /root/.vault_pass          # escreva apenas a senha do vault
```

E use `--vault-password-file /root/.vault_pass` nas execuções (ver
[execucao-automacoes.md](execucao-automacoes.md)).

## 8. Validar a instalação

```bash
cd /opt/ansible

# 1. Ansible enxerga o ansible.cfg e o inventário do repositório
/opt/ansible-venv/bin/ansible --version

# 2. O inventário é lido corretamente
/opt/ansible-venv/bin/ansible-inventory --graph

# 3. Conectividade WinRM com uma estação de teste
/opt/ansible-venv/bin/ansible windows -m ansible.windows.win_ping \
  --ask-vault-pass --limit MTZ_TI10
```

Uma resposta `pong` confirma que credenciais, WinRM e rede estão corretos.

---

## Preparação das estações Windows (alvos)

O provisionamento **não configura o WinRM** — a estação precisa estar acessível antes.
Requisitos em cada máquina de destino:

- Listener **WinRM HTTPS na porta 5986** ativo.
- Autenticação **NTLM** habilitada.
- Regra de firewall liberando a 5986 a partir do servidor de automação.
- A conta do vault (`vault_win_admin_user`) com direitos de administrador local.

O inventário usa `ansible_winrm_server_cert_validation: ignore`, portanto um certificado
autoassinado é aceito (ambiente interno).

Conferência rápida a partir do servidor de automação:

```bash
nc -zv 192.168.0.155 5986
```

---

## Estrutura do repositório

```
/opt/ansible/
├── ansible.cfg                  # inventário padrão, timeouts WinRM, log global
├── requirements.yml             # coleções Ansible necessárias
├── atualizar-inventory.sh       # gera hosts/inventory.yml a partir do Active Directory
├── .env                         # LDAP_PASSWORD (não versionado)
├── inventory/
│   ├── hosts.yml                # INVENTÁRIO PADRÃO — curado, com grupos e vars WinRM
│   └── group_vars/windows/
│       ├── main.yml             # files_root, remote_log_dir, local_log_dir
│       └── vault.yml            # credenciais (Ansible Vault)
├── hosts/
│   └── inventory.yml            # inventário gerado do AD (todas as máquinas ativas)
├── playbooks/
│   ├── setup-completo.yml       # orquestrador geral
│   └── install-safetech.yml     # orquestrador do ERP SafeTech
├── tasks/
│   ├── windows/config-pastas.yml
│   ├── programas/
│   │   ├── install-software.yml
│   │   ├── install-agentes.yml
│   │   └── install-zabbix.yml
│   ├── sft/                     # ambiente legado do ERP SafeTech
│   │   ├── install-orant.yml
│   │   ├── install-oracle-10g.yml
│   │   ├── edit-reg.yml
│   │   ├── mv-tns.yml
│   │   ├── mv-files-sft.yml
│   │   └── mv-fonts.yml
│   └── */common/                # cópias de write-execution-log / configure-oracle-environment
├── files/                       # instaladores (NÃO versionado)
├── logs/                        # log global + logs por host (NÃO versionado)
├── temp/                        # saída bruta do ldapsearch
└── docs/                        # esta documentação
```

### Sobre as pastas `common/` duplicadas

Existem cópias idênticas de `write-execution-log.yml` e `configure-oracle-environment.yml`
em `common/`, `tasks/common/`, `tasks/programas/common/`, `tasks/sft/common/` e
`tasks/windows/common/`.

Isso acontece porque `include_tasks` resolve caminhos relativos **ao diretório do playbook
que está executando**: um playbook em `tasks/sft/` referencia `../common/...`
(= `tasks/common/`), enquanto um playbook em `tasks/windows/` referencia `common/...`
(= `tasks/windows/common/`). Ao alterar um desses arquivos, **replique a mudança em todas
as cópias** — ou refatore para um caminho único.

---

## Variáveis globais

Definidas em [inventory/group_vars/windows/main.yml](../inventory/group_vars/windows/main.yml):

| Variável | Valor | Uso |
|---|---|---|
| `files_root` | `{{ inventory_dir }}/../files` | raiz dos instaladores no controlador |
| `remote_log_dir` | `C:\temp\logs-ansible` | logs gravados na estação |
| `local_log_dir` | `{{ inventory_dir }}/../logs` | logs copiados de volta para o controlador |

Definidas em `vars` do grupo `windows` em [inventory/hosts.yml](../inventory/hosts.yml):

| Variável | Valor |
|---|---|
| `ansible_connection` | `winrm` |
| `ansible_winrm_transport` | `ntlm` |
| `ansible_winrm_server_cert_validation` | `ignore` |
| `ansible_port` | `5986` |
| `ansible_user` / `ansible_password` | vindos do vault |
