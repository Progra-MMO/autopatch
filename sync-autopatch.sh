#!/usr/bin/env bash
# =====================================================================
#  sync-autopatch.sh  -  sincroniza TODOS los archivos de parcheo
#                        (roles ansible + wrapper) en el servidor xtk
# ---------------------------------------------------------------------
#  Para que sirve:
#    Cada vez que hay una mejora o bugfix, en lugar de copiar archivo
#    por archivo, descomprimis este bundle y corres UN comando y queda
#    todo igual a la version de referencia.
#
#  Uso:
#    ./sync-autopatch.sh diff     -> SOLO muestra diferencias (no toca nada)
#    ./sync-autopatch.sh apply    -> aplica los cambios (hace backup .bak.FECHA)
#    ./sync-autopatch.sh list     -> lista los archivos del bundle y su destino
#
#  Rutas (se pueden sobre-escribir por variable de entorno):
#    ANSIBLE_ROOT   donde vive tu arbol ansible   (def: /etc/ansible)
#    WRAPPER        ruta del comando 'autopatch'  (def: /usr/local/sbin/autopatch)
#
#  Ejemplos:
#    ./sync-autopatch.sh diff
#    ANSIBLE_ROOT=/etc/ansible WRAPPER=/usr/local/sbin/autopatch ./sync-autopatch.sh apply
# =====================================================================
set -euo pipefail

# ----------------------------- config --------------------------------
ANSIBLE_ROOT="${ANSIBLE_ROOT:-/etc/ansible}"
WRAPPER="${WRAPPER:-/usr/local/sbin/autopatch}"

# archivos de ENTORNO del usuario que NUNCA se sincronizan (ruta relativa a
# ANSIBLE_ROOT). ansible.cfg es config propia de tu server, no del rol: si lo
# sincronizara te pisaria tu configuracion. Agregar aca cualquier otro archivo
# que debas conservar intacto.
EXCLUDE_REL="ansible.cfg"

# directorio donde esta este script (y el payload)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_ANSIBLE="$HERE/payload/ansible"
PAYLOAD_WRAPPER="$HERE/payload/autopatch"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo '?')"
TS="$(date +%Y%m%d-%H%M%S)"

# colores (si es una terminal)
if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
else
  R=''; G=''; Y=''; B=''; N=''
fi

# ----------------------- mapa origen -> destino ----------------------
# Auto-recorre el payload: no hay lista que mantener cuando se agregan
# archivos nuevos. Emite lineas "SRC<TAB>DST".
build_map() {
  # arbol ansible
  if [[ -d "$PAYLOAD_ANSIBLE" ]]; then
    ( cd "$PAYLOAD_ANSIBLE" && find . -type f ) | sed 's#^\./##' | while read -r rel; do
      # saltar archivos de entorno protegidos
      case " $EXCLUDE_REL " in *" $rel "*) continue ;; esac
      printf '%s\t%s\n' "$PAYLOAD_ANSIBLE/$rel" "$ANSIBLE_ROOT/$rel"
    done
  fi
  # wrapper
  if [[ -f "$PAYLOAD_WRAPPER" ]]; then
    printf '%s\t%s\n' "$PAYLOAD_WRAPPER" "$WRAPPER"
  fi
}

banner() {
  echo "${B}== sync-autopatch (bundle $VERSION) ==${N}"
  echo "   ANSIBLE_ROOT = $ANSIBLE_ROOT"
  echo "   WRAPPER      = $WRAPPER"
  echo
}

# ------------------------------- list --------------------------------
cmd_list() {
  banner
  build_map | while IFS=$'\t' read -r src dst; do
    echo "  $dst"
  done
}

# ------------------------------- diff --------------------------------
cmd_diff() {
  banner
  local nuevos=0 cambiados=0 iguales=0
  while IFS=$'\t' read -r src dst; do
    if [[ ! -f "$dst" ]]; then
      echo "${Y}NUEVO${N}    $dst   (no existe en el servidor, se crearia)"
      nuevos=$((nuevos+1))
    elif diff -q "$dst" "$src" >/dev/null 2>&1; then
      iguales=$((iguales+1))
    else
      echo "${R}CAMBIA${N}   $dst"
      diff -u --label "SERVIDOR: $dst" --label "NUEVO:    $src" "$dst" "$src" || true
      echo
      cambiados=$((cambiados+1))
    fi
  done < <(build_map)
  echo "${B}---------------------------------------------${N}"
  echo "  iguales=$iguales   ${R}cambian=$cambiados${N}   ${Y}nuevos=$nuevos${N}"
  if (( cambiados + nuevos > 0 )); then
    echo "  Para aplicarlo:  ./sync-autopatch.sh apply"
  else
    echo "${G}  Todo ya esta sincronizado.${N}"
  fi
}

# ------------------------------- apply -------------------------------
cmd_apply() {
  banner
  local nuevos=0 cambiados=0 iguales=0 bkdir="$HERE/backup-$TS"
  while IFS=$'\t' read -r src dst; do
    if [[ ! -f "$dst" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst"
      echo "${Y}CREADO${N}   $dst"
      nuevos=$((nuevos+1))
    elif diff -q "$dst" "$src" >/dev/null 2>&1; then
      iguales=$((iguales+1))
    else
      mkdir -p "$bkdir/$(dirname "${dst#/}")"
      cp -a "$dst" "$bkdir/${dst#/}"
      cp -a "$src" "$dst"
      echo "${G}ACTUALIZADO${N}  $dst"
      cambiados=$((cambiados+1))
    fi
  done < <(build_map)

  # el wrapper debe quedar ejecutable
  [[ -f "$WRAPPER" ]] && chmod +x "$WRAPPER"

  echo "${B}---------------------------------------------${N}"
  echo "  iguales=$iguales   actualizados=$cambiados   creados=$nuevos"
  if (( cambiados > 0 )); then
    echo "  Backups de los archivos reemplazados en: $bkdir"
  fi
  echo "${G}  Listo. Recorda que los cambios de ansible toman efecto la proxima"
  echo "  vez que corras el playbook / 'autopatch'.${N}"
}

# ------------------------------- main --------------------------------
case "${1:-}" in
  diff)  cmd_diff ;;
  apply) cmd_apply ;;
  list)  cmd_list ;;
  *)
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^#\s\?//'
    exit 1
    ;;
esac
