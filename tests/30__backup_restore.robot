*** Settings ***
Library     SSHLibrary
Resource    api.resource

*** Test Cases ***
Seed a probe row
    Run on node    runagent -m ${module_id} podman exec hashtopolis-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root hashtopolis -e "CREATE TABLE ci_probe (note varchar(32)); INSERT INTO ci_probe VALUES (\\"pre-backup\\");"'

Back up the module
    ${repo}    ${path} =    Back up the module to the cluster repository    ${module_id}
    Set Global Variable    ${BACKUP_REPO}    ${repo}
    Set Global Variable    ${BACKUP_PATH}    ${path}

Restore into a new instance
    ${rid} =    Restore the module from the cluster repository    ${BACKUP_REPO}    ${BACKUP_PATH}
    Set Global Variable    ${restored_id}    ${rid}
    Should Not Be Equal    ${restored_id}    ${module_id}

The restored instance has data, settings and secrets
    ${out} =    Wait Until Keyword Succeeds    40 times    10 seconds
    ...    Run on node    runagent -m ${restored_id} podman exec hashtopolis-db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root -N hashtopolis -e "SELECT note FROM ci_probe"'
    Should Contain    ${out}    pre-backup
    ${orig} =    Run task    module/${module_id}/get-configuration    {}
    ${cfg} =    Run task    module/${restored_id}/get-configuration    {}
    Should Be Equal    ${cfg['admin_password']}    ${orig['admin_password']}
    Secrets are kept out of the module environment    ${restored_id}
