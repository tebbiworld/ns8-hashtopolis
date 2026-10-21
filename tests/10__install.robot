*** Settings ***
Library     SSHLibrary
Resource    api.resource

*** Variables ***
${CONFIG}    {"host":"hashtopolis.ci.test","lets_encrypt":false,"http2https":true,"public_url":""}

*** Test Cases ***
Install the module
    # The update scenario starts from the last published release and reaches
    # the image under test through update-module below.
    IF    '${SCENARIO}' == 'update'
        ${output}  ${rc} =    Execute Command    add-module ${UPDATE_FROM} 1    return_rc=True
    ELSE
        ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1    return_rc=True
    END
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${module_id}    ${output.module_id}

Configure the module
    Run task    module/${module_id}/configure-module    ${CONFIG}    decode_json=${FALSE}

Hashtopolis answers behind Traefik
    Wait Until Keyword Succeeds    60 times    10 seconds    Frontend and API are served

Remember the secrets before the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Set Global Variable    ${ADMIN_PW_BEFORE}    ${cfg['admin_password']}
    Should Not Be Empty    ${ADMIN_PW_BEFORE}

Update to the image under test
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}
    Run on node    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${module_id}"]}'
    Wait Until Keyword Succeeds    60 times    10 seconds    Frontend and API are served
    # the migration must move the secrets, not regenerate them
    ${pw} =    Run task    module/${module_id}/get-admin-password    {}
    Should Be Equal    ${pw['admin_password']}    ${ADMIN_PW_BEFORE}

Configuration reads back
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${cfg['host']}    hashtopolis.ci.test
    Should Be True    ${cfg['http2https']}
    Should Be True    ${cfg['admin_password_set']}
    Should Be True    'admin_password' not in $cfg

The admin can log in with the stored password
    # also proves that the database accounts work after the MySQL 8.4 upgrade
    ${pw} =    Run task    module/${module_id}/get-admin-password    {}
    ${out} =    Run on node    curl -sSk -o /dev/null -w '\%{http_code}' -u 'admin:${pw['admin_password']}' -X POST -H 'Host: hashtopolis.ci.test' https://127.0.0.1/api/v2/auth/token
    Should Match Regexp    ${out.strip()}    ^20[01]$

Secrets are stored in passwords.env only
    Secrets are kept out of the module environment    ${module_id}

The database runs MySQL 8.4
    ${v} =    Run on node    runagent -m ${module_id} podman exec hashtopolis-db mysqld --version
    Should Contain    ${v}    Ver 8.4.

The mail relay file is written for ssmtp
    # root:mail 0640: only the setgid ssmtp reads it, PHP (www-data) cannot
    ${out} =    Run on node    runagent -m ${module_id} podman exec --user root hashtopolis-backend ls -ln /etc/ssmtp/ssmtp.conf
    Should Match Regexp    ${out}    ^-rw-r-----\\S* 1 0 8
    ${denied} =    Run on node    runagent -m ${module_id} podman exec hashtopolis-backend sh -c 'test -r /etc/ssmtp/ssmtp.conf && echo readable || echo denied'
    Should Be Equal As Strings    ${denied.strip()}    denied

The PHP hardening settings are active
    # CVE-2026-109619 configuration mitigation, mounted from imageroot/php
    ${out} =    Run on node    runagent -m ${module_id} podman exec hashtopolis-backend php -r 'echo ini_get("session.upload_progress.enabled"), ini_get("fatal_error_backtraces");'
    Should Be Equal As Strings    ${out.strip()}    00

The allow-list restricts the route
    Run task    module/${module_id}/configure-module    {"host":"hashtopolis.ci.test","lets_encrypt":false,"http2https":true,"public_url":"","ip_allowlist":["192.0.2.0/24"]}    decode_json=${FALSE}
    ${code} =    Run on node    curl -sSk -o /dev/null -w '\%{http_code}' -H 'Host: hashtopolis.ci.test' https://127.0.0.1/
    Should Be Equal As Strings    ${code.strip()}    403
    Run task    module/${module_id}/configure-module    ${CONFIG}    decode_json=${FALSE}
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal As Integers    ${{ len($cfg['ip_allowlist']) }}    1
    Run task    module/${module_id}/configure-module    {"host":"hashtopolis.ci.test","lets_encrypt":false,"http2https":true,"public_url":"","ip_allowlist":[]}    decode_json=${FALSE}
    Wait Until Keyword Succeeds    30 times    10 seconds    Frontend and API are served

*** Keywords ***
Frontend and API are served
    ${out} =    Run on node    curl -fsSk -H 'Host: hashtopolis.ci.test' https://127.0.0.1/
    Should Contain    ${out}    <app-root
    ${code} =    Run on node    curl -sSk -o /dev/null -w '\%{http_code}' -H 'Host: hashtopolis.ci.test' https://127.0.0.1/api/v2/auth/token
    Should Not Be Equal As Strings    ${code.strip()}    502
