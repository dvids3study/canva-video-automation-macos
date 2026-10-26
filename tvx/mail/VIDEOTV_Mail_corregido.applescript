-- TVX / Apple Mail
-- Acciones: create <ruta_mp4> <referencia> <preview|send> | check <referencia>
-- Seguridad: remitente fijo comprobado antes de solicitar el envio.
-- IMPORTANTE: Mail Drop se configura manualmente en Mail; AppleScript no puede
-- asegurar que una ventana de confirmacion de Mail Drop se acepte automaticamente.

-- Cambia estas dos direcciones si usas otra cuenta o destinatario.
property fromAddress : "you@example.com"
property toAddress : "recipient@example.com"
property mailSubject : "VIDEOTV"

on hasConfiguredAccount()
    tell application "Mail"
        repeat with anAccount in every account
            try
                set accountAddresses to email addresses of anAccount
                repeat with anAddress in accountAddresses
                    if (anAddress as string) is equal to fromAddress then return true
                end repeat
            end try
        end repeat
    end tell
    return false
end hasConfiguredAccount

on run argv
    if (count of argv) < 2 then error "Uso: create archivo referencia modo | check referencia"
    set operationName to item 1 of argv

    -- Permite probar con otro destinatario sin cambiar la configuracion real.
    set recipientAddress to toAddress
    set envTo to system attribute "TVX_MAIL_TO"
    if envTo is not "" then set recipientAddress to envTo

    if operationName is "check" then
        set referenceText to item 2 of argv
        tell application "Mail"
            try
                -- Buscar en el buzon Enviados de todas las cuentas, no solo en
                -- el buzon agregado: con varias cuentas el mensaje puede estar
                -- en el Enviados de iCloud aunque el buzon agregado sea otro.
                set boxes to {}
                try
                    set end of boxes to sent mailbox
                end try
                repeat with anAccount in every account
                    try
                        repeat with aMailbox in mailboxes of anAccount
                            set mbName to name of aMailbox as text
                            if mbName is "Enviados" or mbName is "Sent" then
                                set end of boxes to aMailbox
                            end if
                        end repeat
                    end try
                end repeat

                repeat with mb in boxes
                    try
                        set candidates to (every message of mb whose subject is mailSubject and date sent > ((current date) - 86400))
                        repeat with aMessage in candidates
                            try
                                set bodyText to content of aMessage as text
                                if bodyText contains ("Referencia TVX: " & referenceText) then
                                    set senderAddress to extract address from (sender of aMessage)
                                    if senderAddress is fromAddress then
                                        repeat with aRecipient in to recipients of aMessage
                                            if (address of aRecipient as text) is recipientAddress then return "SENT"
                                        end repeat
                                    end if
                                end if
                            end try
                        end repeat
                    end try
                end repeat
            on error
                -- La comprobacion no disponible nunca cuenta como exito.
                return "UNKNOWN"
            end try
        end tell
        return "PENDING"
    end if

    if operationName is not "create" then error "Operacion desconocida: " & operationName
    if (count of argv) < 4 then error "Falta ruta, referencia o modo"

    set filePath to item 2 of argv
    set referenceText to item 3 of argv
    set sendMode to item 4 of argv
    if sendMode is not "preview" and sendMode is not "send" then error "Modo no permitido"
    set attachedFile to (POSIX file filePath) as alias

    if not my hasConfiguredAccount() then
        error "La cuenta remitente no esta configurada en Apple Mail: " & fromAddress
    end if

    set messageBody to "VIDEOTV" & return & return & "Referencia TVX: " & referenceText & return

tell application "Mail"
    activate

    set draftMessage to make new outgoing message with properties {visible:true, subject:mailSubject, content:messageBody, sender:fromAddress}

    tell draftMessage
        set sender to fromAddress
        make new to recipient at end of to recipients with properties {address:recipientAddress}
    end tell

    tell content of draftMessage
        make new attachment with properties {file name:attachedFile} at after the last paragraph
    end tell

    -- Esperar a que Mail prepare el adjunto
    delay 3

    -- Verificar el remitente
    set selectedSender to sender of draftMessage as string

    if selectedSender does not contain fromAddress then
        error "Mail no selecciono la cuenta remitente esperada. Revisa el borrador."
    end if

    -- Modo de prueba: NO enviar el correo
    if sendMode is "preview" then return "PREVIEW"

    -- Envio real. `send` no devuelve un valor fiable; si Mail falla,
    -- lanzara un error y osascript terminara con codigo distinto de cero.
    send draftMessage
end tell

return "SUBMITTED"
end run
