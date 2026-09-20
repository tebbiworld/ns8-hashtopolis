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
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    # the migration must move the secrets, not regenerate them
    Should Be Equal    ${cfg['admin_password']}    ${ADMIN_PW_BEFORE}

Configuration reads back
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${cfg['host']}    hashtopolis.ci.test
    Should Be True    ${cfg['http2https']}
    Should Not Be Empty    ${cfg['admin_password']}

The admin can log in with the stored password
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    ${out} =    Run on node    curl -sSk -o /dev/null -w '\%{http_code}' -u 'admin:${cfg['admin_password']}' -X POST -H 'Host: hashtopolis.ci.test' https://127.0.0.1/api/v2/auth/token
    Should Match Regexp    ${out.strip()}    ^20[01]$

Secrets are stored in passwords.env only
    Secrets are kept out of the module environment    ${module_id}

*** Keywords ***
Frontend and API are served
    ${out} =    Run on node    curl -fsSk -H 'Host: hashtopolis.ci.test' https://127.0.0.1/
    Should Contain    ${out}    <app-root
    ${code} =    Run on node    curl -sSk -o /dev/null -w '\%{http_code}' -H 'Host: hashtopolis.ci.test' https://127.0.0.1/api/v2/auth/token
    Should Not Be Equal As Strings    ${code.strip()}    502
