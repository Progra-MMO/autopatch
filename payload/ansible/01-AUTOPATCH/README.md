# Playbooks 01-AUTOPATCH — dnf-automatic-redhat

Un playbook **independiente y autocontenido por cada elemento del rol**. Cada uno trae
sus tareas y scripts embebidos, así que **no dependen del árbol `roles/`**: podés copiar
un solo `.yml` al Satellite / AWX / Tower y ejecutarlo suelto.

## Qué hace cada uno

| Playbook | Corre en | Qué configura |
|----------|----------|---------------|
| `01-mail_relay.yml` | todos los RHEL | MTA local (sendmail/postfix) como smarthost hacia `smtp_server` |
| `02-dnf_automatic.yml` | todos los RHEL | Parcheo diario con dnf-automatic (23:00 por defecto) |
| `03-kpatch.yml` | todos los RHEL | Live kernel patching (kpatch) |
| `04-kernel_cleanup.yml` | todos los RHEL | Borra kernels viejos tras cada reinicio |
| `05-scheduled_reboot.yml` | todos los RHEL | Reinicio programado (sábados 15:00 por defecto) |
| `06-patch_report.yml` | todos los RHEL | Script de reporte por servidor (modo `pull` por defecto) |
| `07-patch_puller.yml` | **Servidor 1** | Recoge por SSH, consolida y manda **UN** mail |
| `08-patch_collector.yml` | colector (opcional) | Alternativa **push**: recibe por scp y consolida (crea usuario) |

## Orden de ejecución sugerido

Sobre los servidores a parchear (grupo `redhat_servers`):

```bash
ansible-playbook -i inventario.example.ini 01-mail_relay.yml -e smtp_server=smtp.tucliente.com
ansible-playbook -i inventario.example.ini 02-dnf_automatic.yml
ansible-playbook -i inventario.example.ini 03-kpatch.yml
ansible-playbook -i inventario.example.ini 04-kernel_cleanup.yml
ansible-playbook -i inventario.example.ini 05-scheduled_reboot.yml
ansible-playbook -i inventario.example.ini 06-patch_report.yml
```

Sobre el Servidor 1 (el que junta y manda el mail único), modo **pull** (recomendado, no crea usuarios):

```bash
ansible-playbook -i inventario.example.ini 07-patch_puller.yml -e target_hosts=puller \
  -e report_to=infra@tucliente.com
```

> Alternativa **push** (crea un usuario de servicio en el colector): usá `08-patch_collector.yml`
> y ejecutá `06-patch_report.yml` con `-e report_mode=central`. No lo uses si el modo pull ya te sirve.

## Variables útiles (se pasan con `-e`)

- `target_hosts` — grupo/host destino. Por defecto `redhat_servers` (01-06), `puller` (07), `collector` (08).
- `smtp_server` — **obligatoria** en `01-mail_relay.yml`.
- `patch_oncalendar` — horario de parcheo (default `*-*-* 23:00:00`).
- `reboot_oncalendar` — horario de reinicio (default `Sat *-*-* 15:00:00`).
- `report_mode` — `pull` (default) | `local` | `central`.
- `report_file` — dónde deja el fragmento en modo pull (default `/tmp/patch-report/latest.html`).
- `report_owner` — dueño del archivo en modo pull (default `svc-ar-checklist`); permite que el
  Servidor 1 lo lea/descargue. Si no querés cambiar el dueño, pasá `-e report_owner=""`.
- `puller_ssh_user` / `puller_ssh_key` — usuario y clave que **ya existen** en el Servidor 1.
- `puller_oncalendar` — horario del mail consolidado (default `*-*-* 23:40:00`).

## Notas

- Los playbooks son idempotentes; podés correrlos varias veces.
- No crean usuarios en los servidores (excepto `08-patch_collector.yml`, que es el modo push).
- `kpatch`, el reinicio y los timers de systemd sólo se pueden probar de verdad en un RHEL real.
- El módulo `community.crypto` sólo se usa en `06` cuando `report_mode=central`; en `pull`/`local`
  sólo se usa `ansible.builtin`.
