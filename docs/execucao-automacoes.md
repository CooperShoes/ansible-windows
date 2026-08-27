# Execução das automações

Todos os comandos devem ser executados **de dentro de `/opt/ansible`** — o
[ansible.cfg](../ansible.cfg) do repositório define o inventário padrão, os timeouts de
WinRM e o arquivo de log global, e só é carregado a partir desse diretório.

```bash
cd /opt/ansible
```

Se o venv não estiver no PATH, prefixe os comandos com `/opt/ansible-venv/bin/`.

---

## Antes de rodar: o checklist

1. `files/` está preenchida com os instaladores ([ver guia de instalação](instalacao-servidor.md#5-copiar-os-instaladores-files)).
2. A estação está no inventário [inventory/hosts.yml](../inventory/hosts.yml).
3. A estação responde ao ping WinRM:
   ```bash
   ansible windows -m ansible.windows.win_ping --ask-vault-pass --limit MTZ_TI10
   ```

> **Todos os playbooks rodam com `serial: 1`** — uma estação por vez. Provisionar 10
> máquinas leva aproximadamente 10× o tempo de uma. Instalações pesadas (Oracle 10G,
> Microsoft 365) levam vários minutos por host.

---

## Senha do vault

Toda execução precisa da senha do Ansible Vault. Duas formas:

```bash
# Digitando a senha a cada execução
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass

# Usando arquivo de senha (sem interação — necessário para agendamentos/cron)
ansible-playbook playbooks/setup-completo.yml --vault-password-file /root/.vault_pass
```

Nos exemplos abaixo usamos `--ask-vault-pass`; substitua conforme o caso.

---

## Provisionamento completo de uma estação

Este é o caminho normal para uma máquina nova:

```bash
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit MTZ_TI10
```

O [setup-completo.yml](../playbooks/setup-completo.yml) executa, nesta ordem:

| # | Etapa | Playbook | O que faz |
|---|---|---|---|
| 1 | Pastas padrão | `tasks/windows/config-pastas.yml` | Cria `C:\temp` e `C:\lixo` |
| 2 | Software base | `tasks/programas/install-software.yml` | Chocolatey, Google Chrome (MSI Enterprise), WinRAR, 7-Zip, Adobe Reader |
| 3 | Agentes corporativos | `tasks/programas/install-agentes.yml` | AnyDesk, BitDefender, WatchGuard EDR, Microsoft 365 via ODT |
| 4 | ERP SafeTech | `playbooks/install-safetech.yml` | Orant, registro 64BITS, Oracle Client 10G, arquivos do ERP, fontes, TNS |

> ⚠️ **Sem `--limit`, o playbook roda em TODAS as estações do inventário.** Sempre
> restrinja o alvo, a menos que a intenção seja realmente provisionar o parque inteiro.

---

## Somente o ambiente SafeTech

```bash
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass --limit MTZ_MODM01
```

O [install-safetech.yml](../playbooks/install-safetech.yml) executa em sequência:

| # | Etapa | Tags | Descrição |
|---|---|---|---|
| 1 | `install-orant.yml` | `orant` | Copia e descompacta `orant.zip`, instala em `C:\orant` via robocopy. Falha se `orant\BIN\SQLPLUS.EXE` não existir no pacote |
| 2 | `edit-reg.yml` | `orant`, `registro` | Importa `64BITS.reg` no registro |
| 3 | `install-oracle-10g.yml` | `oracle10g` | Instala o Oracle Client 10G em `C:\oracle\product\10.2.0\client_1` via response file; ajusta `PATH` e `TNS_ADMIN` |
| 4 | `mv-files-sft.yml` | `arquivos_erp` | Distribui `d2kwut60.dll`, `D2KWUT60.pll/.plx` para `System`, `System32` e `SysWOW64`; copia `SISTEMAS.lnk` |
| 5 | `mv-fonts.yml` | `fontes` | Instala as fontes `.ttf`/`.otf` ainda ausentes em `C:\Windows\Fonts` |
| 6 | `mv-tns.yml` | `tns` | Copia `TNSNAMES.ORA` para o Orant (`NET80\ADMIN`) e para o client 10G; valida com `tnsping COOPER` |
| 7 | `edit-reg.yml` | `reg` | Reaplica `64BITS.reg` ao final |

**A ordem importa.** O `mv-tns.yml` interrompe a execução (`assert`) se o Orant ou o
Oracle Client 10G não estiverem instalados.

> Nota: `edit-reg.yml` aparece duas vezes (etapas 2 e 7), por isso o `.reg` é importado
> duas vezes numa execução completa. A operação é idempotente, mas é uma duplicação
> intencional de segurança — não um erro de execução.

### Rodar apenas parte do SafeTech (tags)

```bash
# Só o Oracle Client 10G
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass \
  --limit MTZ_MODM01 --tags oracle10g

# Só TNS e fontes
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass \
  --limit MTZ_MODM01 --tags "tns,fontes"

# Tudo, menos o registro
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass \
  --limit MTZ_MODM01 --skip-tags registro
```

---

## Rodar uma etapa isolada

Cada arquivo em `tasks/` é um playbook completo e pode ser executado sozinho:

```bash
ansible-playbook tasks/programas/install-software.yml --ask-vault-pass --limit MTZ_TI10
ansible-playbook tasks/programas/install-agentes.yml  --ask-vault-pass --limit MTZ_TI10
ansible-playbook tasks/windows/config-pastas.yml      --ask-vault-pass --limit MTZ_TI10
ansible-playbook tasks/sft/mv-tns.yml                 --ask-vault-pass --limit MTZ_MODM01
```

Pular os pacotes opcionais do software base (7-Zip e Adobe Reader):

```bash
ansible-playbook tasks/programas/install-software.yml --ask-vault-pass \
  --limit MTZ_TI10 --skip-tags opcional
```

---

## Selecionando alvos (`--limit`)

Os grupos definidos em [inventory/hosts.yml](../inventory/hosts.yml):

| Grupo | Setor |
|---|---|
| `estacoes_modelagem` | Modelagem |
| `estacoes_ti` | TI |
| `estacoes_notas` | Notas fiscais |
| `estacoes_sac` | SAC |

Todos pertencem ao grupo pai `windows`.

```bash
--limit MTZ_TI10                  # um host
--limit estacoes_ti               # um grupo inteiro
--limit MTZ_TI10,MTZ_TI11         # vários hosts
--limit 'estacoes_sac:!MTZ_SAC01' # o grupo, exceto um host
```

Listar o que o inventário enxerga antes de executar:

```bash
ansible-inventory --graph
ansible-inventory --graph estacoes_ti
```

---

## Ensaio e depuração

```bash
# Simulação (não altera nada nas estações)
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit MTZ_TI10 --check

# Saída detalhada
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit MTZ_TI10 -vvv

# Retomar a partir de uma task específica
ansible-playbook playbooks/install-safetech.yml --ask-vault-pass --limit MTZ_TI10 \
  --start-at-task "Copiar tnsnames.ora para o client 10g"

# Listar as tasks sem executar
ansible-playbook playbooks/setup-completo.yml --list-tasks
```

> `--check` tem utilidade limitada aqui: muitas etapas usam `win_command`/`win_shell`,
> que não suportam modo de simulação e são apenas puladas.

---

## Onde ficam os logs

Cada etapa grava um resumo em dois lugares (ver
[common/write-execution-log.yml](../common/write-execution-log.yml)):

| Local | Caminho |
|---|---|
| Na estação Windows | `C:\temp\logs-ansible\<etapa>.log` |
| No servidor de automação | `/opt/ansible/logs/<HOSTNAME>/<etapa>.log` |
| Log global do Ansible | `/opt/ansible/logs/ansible-execucao.log` |

Exemplo do que existe hoje:

```
logs/
├── ansible-execucao.log
├── MTZ_MODM01/
│   ├── config-pastas.log
│   ├── install-software.log
│   ├── install-agentes.log
│   ├── install-orant.log
│   ├── install-oracle-10g.log
│   ├── oracle-10g-run.log                    # log do .bat de instalação do Oracle
│   ├── oracle-inventory-installActions.log   # log do Oracle Universal Installer
│   ├── mv-tns.log
│   ├── mv-files-sft.log
│   ├── mv-fonts.log
│   └── edit-reg.log
└── MTZ_MODTC03/...
```

A pasta `logs/` é ignorada pelo Git — os logs ficam apenas no servidor.

Acompanhar uma execução em andamento a partir de outro terminal:

```bash
tail -f /opt/ansible/logs/ansible-execucao.log
```

Além dos arquivos, cada playbook imprime um bloco `debug` com o resumo `OK` / `FALHOU`
por componente ao final da execução em cada host.

---

## Atualizar o inventário a partir do Active Directory

O script [atualizar-inventory.sh](../atualizar-inventory.sh) consulta o AD via
`ldapsearch` e gera uma lista de todas as máquinas **não desabilitadas**:

```bash
sudo /opt/ansible/atualizar-inventory.sh
```

- Lê a senha de `/opt/ansible/.env` (`LDAP_PASSWORD`).
- Grava a saída bruta em `temp/hosts.txt`.
- Gera `hosts/inventory.yml` com todos os hosts sob o grupo `windows`.

> **Atenção — este arquivo não é o inventário usado nas execuções.** O `ansible.cfg`
> aponta para `inventory/hosts.yml`, que é curado manualmente e é o único que contém os
> grupos por setor, os endereços IP e as variáveis de conexão WinRM.
>
> O `hosts/inventory.yml` é **material de consulta**: use-o para descobrir quais máquinas
> existem no domínio e então adicionar manualmente as relevantes em
> `inventory/hosts.yml`. Executar diretamente contra ele
> (`ansible-playbook -i hosts/inventory.yml ...`) não funciona sem também fornecer as
> variáveis de conexão do grupo `windows`.

### Adicionar uma estação nova

Edite [inventory/hosts.yml](../inventory/hosts.yml) e inclua o host no grupo do setor:

```yaml
        estacoes_ti:
          hosts:
            MTZ_TI12:
              ansible_host: 192.168.0.201
```

Valide e provisione:

```bash
ansible-inventory --graph estacoes_ti
ansible windows -m ansible.windows.win_ping --ask-vault-pass --limit MTZ_TI12
ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit MTZ_TI12
```

---

## Zabbix (execução separada)

O [install-zabbix.yml](../tasks/programas/install-zabbix.yml) **não faz parte do
`setup-completo.yml`** e é executado sob demanda. Ele instala o Zabbix Agent 2, inicia o
serviço e cadastra o host via API do Zabbix (`http://192.168.0.133:8080`).

```bash
ansible-playbook tasks/programas/install-zabbix.yml --ask-vault-pass --limit MTZ_TI10 \
  -e zabbix_api_user=<usuario> -e zabbix_api_password=<senha> -e zabbix_group_id=<id>
```

> **Pendências conhecidas neste playbook:**
> - `zabbix_api_user` e `zabbix_api_password` não estão definidos em lugar nenhum do
>   repositório — precisam ser passados com `-e` ou movidos para o vault.
> - `zabbix_group_id` está vazio no arquivo; sem um ID de grupo válido, a chamada
>   `host.create` da API falha.
> - O caminho do MSI está fixado em `/opt/ansible/files/instaladores/...`, não usa
>   `files_root`.

---

## Referência rápida de comandos

| Objetivo | Comando |
|---|---|
| Testar conexão | `ansible windows -m ansible.windows.win_ping --ask-vault-pass --limit HOST` |
| Provisionar estação nova | `ansible-playbook playbooks/setup-completo.yml --ask-vault-pass --limit HOST` |
| Só o SafeTech | `ansible-playbook playbooks/install-safetech.yml --ask-vault-pass --limit HOST` |
| Só software base | `ansible-playbook tasks/programas/install-software.yml --ask-vault-pass --limit HOST` |
| Só agentes | `ansible-playbook tasks/programas/install-agentes.yml --ask-vault-pass --limit HOST` |
| Só Oracle 10G | `ansible-playbook playbooks/install-safetech.yml --ask-vault-pass --limit HOST --tags oracle10g` |
| Ver inventário | `ansible-inventory --graph` |
| Ver/editar credenciais | `ansible-vault view\|edit inventory/group_vars/windows/vault.yml` |
| Atualizar lista do AD | `sudo ./atualizar-inventory.sh` |
| Acompanhar execução | `tail -f logs/ansible-execucao.log` |
