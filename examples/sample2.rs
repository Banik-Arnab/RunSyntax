// declaration with initialiser, precedence, float widening, nested scopes
int a = 5;
int b = 10;
int c;
c = a + b * 2;
float f = 3;
f = f / 2.5;
bool ok = (a < b) && !(c == 0);
{
    int a = 99;       // shadows outer a (different scope)
    print a;
    {
        bool deep = true;
        if (deep || ok) { print c; }
    }
}
print a;
