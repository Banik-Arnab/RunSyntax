const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const app = express();
// Allow the page to be opened from another origin too (e.g. VS Code Live Server)
app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    next();
});
app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, '..', 'frontend')));

const COMPILER = path.join(__dirname, '..', 'compiler',
    process.platform === 'win32' ? 'runsyntax.exe' : 'runsyntax');

app.post('/api/compile', (req, res) => {
    const code = (req.body && req.body.code) || '';
    if (typeof code !== 'string' || code.length === 0) {
        return res.status(400).json({ error: 'Empty source' });
    }

    // Clear message instead of a crash when the compiler was never built.
    if (!fs.existsSync(COMPILER)) {
        return res.status(500).json({
            error: 'Compiler not found: ' + COMPILER +
                   '  -> open the MSYS2 UCRT64 shell, run: cd compiler && make'
        });
    }

    const id = crypto.randomBytes(6).toString('hex');
    const srcPath = path.join(os.tmpdir(), `runsyntax_${id}.src`);
    fs.writeFileSync(srcPath, code, 'utf8');

    // 'error' and 'close' can both fire; answer the request only once.
    let responded = false;
    const reply = (status, body) => {
        if (responded) return;
        responded = true;
        try { fs.unlinkSync(srcPath); } catch (_) {}
        res.status(status).json(body);
    };

    const child = spawn(COMPILER, [srcPath], { timeout: 8000 });
    let out = '', err = '';

    child.stdout.on('data', d => out += d.toString());
    child.stderr.on('data', d => err += d.toString());

    child.on('error', e => reply(500, { error: 'Compiler spawn failed: ' + e.message }));

    child.on('close', (codeExit) => {
        const result = parseCompilerOutput(out, err, codeExit);
        if (codeExit === null || codeExit > 3) {
            result.error = 'Compiler crashed (exit code ' + codeExit + ')';
        }
        reply(200, result);
    });
});

function parseCompilerOutput(stdout, stderr, exitCode) {
    const ast = [];
    const symbols = [];
    const tac = [];
    const tokens = [];
    const lexErrors = [];
    const synErrors = [];
    const semErrors = [];
    let syntaxOk = false, reachedTAC = false;

    for (const line of stdout.split(/\r?\n/)) {
        if (line === '===SYNTAX_OK===') syntaxOk = true;
        else if (line === '===TAC===') reachedTAC = true;
        else if (line.startsWith('TOKEN|')) {
            const p = line.split('|');
            tokens.push({ line: Number(p[1]), kind: p[2], lexeme: p.slice(3).join('|') });
        } else if (line.startsWith('SYMBOL|')) {
            const p = line.split('|');
            symbols.push({ name: p[1], type: p[2], scope: Number(p[3]), line: Number(p[4]) });
        } else if (line.startsWith('TAC|')) {
            tac.push(line.substring(4));
        } else if (line.startsWith('===AST===')) { /* marker */ }
        else if (line.length && !line.startsWith('===') && reachedTAC === false) {
            ast.push(line);
        }
    }

    for (const line of stderr.split(/\r?\n/)) {
        if (line.startsWith('LEX_ERROR|')) {
            const p = line.split('|');
            lexErrors.push({ line: Number(p[1]), message: p[2], lexeme: p.slice(3).join('|') });
        } else if (line.startsWith('SYNTAX_ERROR|')) {
            const p = line.split('|');
            synErrors.push({ line: Number(p[1]), message: p[2] });
        } else if (line.startsWith('SEM_ERROR|')) {
            const p = line.split('|');
            semErrors.push({ line: Number(p[1]), message: p[2], detail: p.slice(3).join('|') });
        }
    }

    return {
        success: exitCode === 0 && lexErrors.length === 0 && synErrors.length === 0 && semErrors.length === 0,
        lexical: { success: lexErrors.length === 0, errors: lexErrors, tokens },
        syntax:  { success: synErrors.length === 0, errors: synErrors },
        ast: ast.join('\n'),
        symbolTable: symbols,
        semantic: { success: semErrors.length === 0, errors: semErrors },
        tac,
        summary: {
            lexical:  lexErrors.length === 0,
            syntax:   synErrors.length === 0,
            ast:      syntaxOk,
            semantic: semErrors.length === 0,
            tac:      reachedTAC
        }
    };
}

process.on('uncaughtException', e => console.error('Unhandled error:', e));
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`RunSyntax backend on http://localhost:${PORT}`);
    console.log(fs.existsSync(COMPILER) ? `Using compiler: ${COMPILER}`
        : `WARNING: compiler not built yet (${COMPILER}). Run: cd compiler && make`);
});